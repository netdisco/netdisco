package App::Netdisco::Worker::Plugin::Discover::VLANs;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Worker::Plugin;
use App::Netdisco::Transport::SNMP ();

use aliased 'App::Netdisco::Worker::Status';
use List::MoreUtils 'uniq';

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  return unless $device->in_storage;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  my $v_name  = $snmp->v_name;
  my $v_index = $snmp->v_index;

  # cache the device ports to save hitting the database for many single rows
  my $device_ports = vars->{'device_ports'}
    || { map {($_->port => $_)} $device->ports->all };

  my $i_vlan      = $snmp->i_vlan;
  my $i_vlan_type = $snmp->i_vlan_type;
  my $interfaces  = $snmp->interfaces;
  my $i_vlan_membership          = $snmp->i_vlan_membership;
  my $i_vlan_membership_untagged = $snmp->i_vlan_membership_untagged;

  my %p_seen = ();
  my @portvlans = ();
  my @active_ports = uniq (keys %$i_vlan_membership_untagged, keys %$i_vlan_membership);

  # build port vlans suitable for DBIC
  foreach my $entry (@active_ports) {
      my $port = $interfaces->{$entry} or next;

      if (!defined $device_ports->{$port}) {
          debug sprintf ' [%s] vlans - local port %s already skipped, ignoring',
            $device->ip, $port;
          next;
      }

      my %this_port_vlans = ();
      my $type = $i_vlan_type->{$entry};

      foreach my $vlan (@{ $i_vlan_membership_untagged->{$entry} || [] }) {
          next unless $vlan;
          next if $this_port_vlans{$vlan};
          my $native = ((defined $i_vlan->{$entry})
                          and ($vlan eq $i_vlan->{$entry})) ? 't' : 'f';

          push @portvlans, {
              port => $port,
              vlan => $vlan,
              native => $native,
              egress_tag => 'f',
              vlantype => $type,
              last_discover => \'now()',
          };

          ++$this_port_vlans{$vlan};
          ++$p_seen{$vlan};
      }

      foreach my $vlan (@{ $i_vlan_membership->{$entry} || [] }) {
          next unless $vlan;
          next if $this_port_vlans{$vlan};
          my $native = ((defined $i_vlan->{$entry})
                          and ($vlan eq $i_vlan->{$entry})) ? 't' : 'f';

          push @portvlans, {
              port => $port,
              vlan => $vlan,
              native => $native,
              egress_tag => ($native eq 't' ? 'f' : 't'),
              vlantype => $type,
              last_discover => \'now()',
          };

          ++$this_port_vlans{$vlan};
          ++$p_seen{$vlan};
      }
  }

  schema('netdisco')->txn_do(sub {
    my $gone = $device->port_vlans->delete;
    debug sprintf ' [%s] vlans - removed %d port VLANs',
      $device->ip, $gone;
    $device->port_vlans->populate(\@portvlans);

    debug sprintf ' [%s] vlans - added %d new port VLANs',
      $device->ip, scalar @portvlans;
  });

  my %d_seen = ();
  my @devicevlans = ();

  # add named vlans to the device
  foreach my $entry (keys %$v_name) {
      my $vlan = $v_index->{$entry};
      next unless $vlan;
      next unless defined $vlan and $vlan;
      ++$d_seen{$vlan};

      push @devicevlans, {
          vlan => $vlan,
          description => $v_name->{$entry},
          last_discover => \'now()',
      };
  }

  # also add unnamed vlans to the device
  foreach my $vlan (keys %p_seen) {
      next unless $vlan;
      next if $d_seen{$vlan};
      push @devicevlans, {
          vlan => $vlan,
          description => (sprintf "VLAN %d", $vlan),
          last_discover => \'now()',
      };
  }

  schema('netdisco')->txn_do(sub {
    my $gone = $device->vlans->delete;
    debug sprintf ' [%s] vlans - removed %d device VLANs',
      $device->ip, $gone;
    $device->vlans->populate(\@devicevlans);

    debug sprintf ' [%s] vlans - added %d new device VLANs',
      $device->ip, scalar @devicevlans;
  });

  return Status->info(sprintf ' [%s] vlans - discovered for ports and device',
    $device->ip);
});

true;
