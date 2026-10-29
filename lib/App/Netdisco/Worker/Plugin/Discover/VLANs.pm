package App::Netdisco::Worker::Plugin::Discover::VLANs;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Worker::Plugin;
use App::Netdisco::Transport::SNMP ();

use aliased 'App::Netdisco::Worker::Status';
use List::MoreUtils 'uniq';
use App::Netdisco::Util::SNMPText 'decode_snmp_text';
use App::Netdisco::Util::SNMP qw/walk_mark incomplete_walks_for incomplete_walk_message
  incomplete_walk_level/;

# a walk that was cut short must not look like an emptied table, so the stored
# rows stand and the hook payload shows them rather than the partial walk
sub _keep_stored_device_vlans {
  my ($device, @incomplete) = @_;
  vars->{'hook_data'}->{'vlans'} = [ $device->vlans->search(undef, {
    columns => [qw/vlan description/], order_by => 'vlan',
    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
  })->all ];
  my $message = incomplete_walk_message($device, 'device_port_vlan and device_vlan', @incomplete);
  warning $message;
  return $message;
}

sub _store_device_vlans {
  my ($device, $v_name, $v_index, $p_seen) = @_;
  my (%d_seen, @devicevlans);

  # sorted, and the first name for a VLAN number wins, so every run agrees
  foreach my $entry (sort keys %$v_name) {
      my $vlan = $v_index->{$entry};
      next unless $vlan;
      next if $d_seen{$vlan}++;

      push @devicevlans, {
          ip => $device->ip,
          vlan => $vlan,
          description => decode_snmp_text($v_name->{$entry}, $device, "vlan $vlan name"),
          last_discover => \'LOCALTIMESTAMP',
      };
  }

  # also add unnamed vlans to the device
  foreach my $vlan (sort { $a <=> $b } keys %$p_seen) {
      next unless $vlan;
      next if $d_seen{$vlan};
      push @devicevlans, {
          ip => $device->ip,
          vlan => $vlan,
          description => (sprintf "VLAN %d", $vlan),
          last_discover => \'LOCALTIMESTAMP',
      };
  }

  # support for Hooks
  vars->{'hook_data'}->{'vlans'} = [ map {{
    vlan => $_->{vlan}, description => $_->{description},
    last_discover => $_->{last_discover},
  }} @devicevlans ];

  schema('netdisco')->txn_do(sub {
    my $rs = schema('netdisco')->resultset('DeviceVlan');
    $rs->upsert(\@devicevlans, { touch => ['last_discover'] });
    my $gone = $rs->remove_unseen({ ip => $device->ip },
      [ map {{ vlan => $_->{vlan} }} @devicevlans ]);
    debug sprintf ' [%s] vlans - removed %d device VLANs',
      $device->ip, $gone;

    debug sprintf ' [%s] vlans - wrote %d device VLANs',
      $device->ip, scalar @devicevlans;
  });
  return;
}

sub _port_vlan_rows {
  my ($device, $walked, $device_ports) = @_;
  my ($i_vlan, $i_vlan_type, $interfaces, $i_vlan_membership,
      $i_vlan_membership_untagged) = @{$walked}{qw/i_vlan i_vlan_type
        interfaces i_vlan_membership i_vlan_membership_untagged/};

  my (%p_seen, %row_seen, @portvlans);
  my @active_ports = uniq (keys %$i_vlan_membership_untagged, keys %$i_vlan_membership);

  # sorted, and the first entry for a port/vlan/native key wins: two interface
  # entries can carry one port name, and an upsert refuses a duplicate key
  foreach my $entry (sort @active_ports) {
      my $port = $interfaces->{$entry} or next;

      if (!defined $device_ports->{$port}) {
          debug sprintf ' [%s] vlans - local port %s already skipped, ignoring',
            $device->ip, $port;
          next;
      }

      my %this_port_vlans = ();
      my $type = $i_vlan_type->{$entry};

      foreach my $set ([ $i_vlan_membership_untagged->{$entry}, 0 ],
                       [ $i_vlan_membership->{$entry}, 1 ]) {
          foreach my $vlan (@{ $set->[0] || [] }) {
              next unless $vlan;
              next if $this_port_vlans{$vlan};
              my $native = ((defined $i_vlan->{$entry})
                              and ($vlan eq $i_vlan->{$entry})) ? 't' : 'f';
              ++$this_port_vlans{$vlan};
              ++$p_seen{$vlan};
              next if $row_seen{join "\0", $port, $vlan, $native}++;

              push @portvlans, {
                  ip => $device->ip,
                  port => $port,
                  vlan => $vlan,
                  native => $native,
                  egress_tag => ($set->[1] && $native eq 'f' ? 't' : 'f'),
                  vlantype => $type,
                  last_discover => \'LOCALTIMESTAMP',
              };
          }
      }
  }
  return (\@portvlans, \%p_seen);
}

sub _store_port_vlans {
  my ($device, $portvlans) = @_;

  schema('netdisco')->txn_do(sub {
    my $rs = schema('netdisco')->resultset('DevicePortVlan');
    $rs->upsert($portvlans, { touch => ['last_discover'] });
    my $gone = $rs->remove_unseen({ ip => $device->ip },
      [ map {{ port => $_->{port}, vlan => $_->{vlan}, native => $_->{native} }} @$portvlans ]);
    debug sprintf ' [%s] vlans - removed %d port VLANs',
      $device->ip, $gone;

    debug sprintf ' [%s] vlans - wrote %d port VLANs',
      $device->ip, scalar @$portvlans;
  });
  return;
}

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  return unless $device->in_storage;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  my $walk_mark = walk_mark($snmp);
  my $v_name  = $snmp->v_name;
  my $v_index = $snmp->v_index;

  # every port VLAN table is read before the guard, which looks at the walks
  # read so far
  my %walked = map {($_ => $snmp->$_)} qw/i_vlan i_vlan_type interfaces
    i_vlan_membership i_vlan_membership_untagged/;

  # cache the device ports to save hitting the database for many single rows
  my $device_ports = vars->{'device_ports'}
    || { map {($_->port => $_)} $device->ports->all };

  my @incomplete = incomplete_walks_for($device, $snmp, $walk_mark, qw/
    v_name v_index i_vlan i_vlan_type i_vlan_membership
    i_vlan_membership_untagged interfaces/);
  my $level = incomplete_walk_level(@incomplete);
  my $status = sprintf ' [%s] vlans - discovered for ports and device',
    $device->ip;

  if (scalar @incomplete) {
      $status = _keep_stored_device_vlans($device, @incomplete);
  }
  else {
      my ($portvlans, $p_seen) = _port_vlan_rows($device, \%walked, $device_ports);
      _store_port_vlans($device, $portvlans);
      _store_device_vlans($device, $v_name, $v_index, $p_seen);
  }

  return Status->$level($status);
});

true;
