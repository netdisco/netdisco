package App::Netdisco::Worker::Plugin::Discover::VLANs;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use Dancer::Plugin::DBIC 'schema';

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  return unless $device->in_storage;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  my $v_name  = $snmp->v_name;
  my $v_index = $snmp->v_index;

  # build device vlans suitable for DBIC
  my %v_seen = ();
  my @devicevlans;
  foreach my $entry (keys %$v_name) {
      my $vlan = $v_index->{$entry};
      next unless defined $vlan and $vlan;
      ++$v_seen{$vlan};

      push @devicevlans, {
          vlan => $vlan,
          description => $v_name->{$entry},
          last_discover => \'now()',
      };
  }

  # cache the device ports to save hitting the database for many single rows
  my $device_ports = vars->{'device_ports'}
    || { map {($_->port => $_)} $device->ports->all };

  my $i_vlan            = $snmp->i_vlan;
  my $i_vlan_membership = $snmp->i_vlan_membership;
  my $i_vlan_type       = $snmp->i_vlan_type;
  my $interfaces        = $snmp->interfaces;

  # build device port vlans suitable for DBIC
  my @portvlans = ();
  foreach my $entry (keys %$i_vlan_membership) {
      my %port_vseen = ();
      my $port = $interfaces->{$entry} or next;

      if (!defined $device_ports->{$port}) {
          debug sprintf ' [%s] vlans - local port %s already skipped, ignoring',
            $device->ip, $port;
          next;
      }

      my $type = $i_vlan_type->{$entry};

      foreach my $vlan (@{ $i_vlan_membership->{$entry} }) {
          next unless defined $vlan and $vlan;
          next if ++$port_vseen{$vlan} > 1;

          my $native = ((defined $i_vlan->{$entry}) and ($vlan eq $i_vlan->{$entry})) ? "t" : "f";
          push @portvlans, {
              port => $port,
              vlan => $vlan,
              native => $native,
              vlantype => $type,
              last_discover => \'now()',
          };

          next if $v_seen{$vlan};

          # also add an unnamed vlan to the device
          push @devicevlans, {
              vlan => $vlan,
              description => (sprintf "VLAN %d", $vlan),
              last_discover => \'now()',
          };
          ++$v_seen{$vlan};
      }
  }

  schema('netdisco')->txn_do(sub {
    my $gone = $device->vlans->delete;
    debug sprintf ' [%s] vlans - removed %d device VLANs',
      $device->ip, $gone;
    $device->vlans->populate(\@devicevlans);
    debug sprintf ' [%s] vlans - added %d new device VLANs',
      $device->ip, scalar @devicevlans;
  });

  schema('netdisco')->txn_do(sub {
    my $gone = $device->port_vlans->delete;
    debug sprintf ' [%s] vlans - removed %d port VLANs',
      $device->ip, $gone;
    $device->port_vlans->populate(\@portvlans);

    return Status->info(sprintf ' [%s] vlans - added %d new port VLANs',
      $device->ip, scalar @portvlans);
  });
});

true;
