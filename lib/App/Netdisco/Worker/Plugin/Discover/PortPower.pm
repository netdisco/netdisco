package App::Netdisco::Worker::Plugin::Discover::PortPower;

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

  my $p_watts  = $snmp->peth_power_watts;
  my $p_status = $snmp->peth_power_status;

  if (!defined $p_watts) {
      return Status->info(sprintf ' [%s] power - 0 power modules', $device->ip);
  }

  # build device module power info suitable for DBIC
  my @devicepower;
  foreach my $entry (keys %$p_watts) {
      push @devicepower, {
          module => $entry,
          power  => $p_watts->{$entry},
          status => $p_status->{$entry},
      };
  }

  # cache the device ports to save hitting the database for many single rows
  my $device_ports = vars->{'device_ports'}
    || { map {($_->port => $_)} $device->ports->all };

  my $interfaces = $snmp->interfaces;
  my $p_ifindex  = $snmp->peth_port_ifindex;
  my $p_admin    = $snmp->peth_port_admin;
  my $p_pstatus  = $snmp->peth_port_status;
  my $p_class    = $snmp->peth_port_class;
  my $p_power    = $snmp->peth_port_power;

  # build device port power info suitable for DBIC
  my @portpower;
  my %seen_pp = ();
  foreach my $entry (keys %$p_ifindex) {
      # WRT 475 this is SAFE because we check against known ports below
      my $port = $interfaces->{ $p_ifindex->{$entry} } or next;

      # 1463 sometimes see second entry for the same port
      next if $seen_pp{$port};

      if (!defined $device_ports->{$port}) {
          debug sprintf ' [%s] power - local port %s already skipped, ignoring',
            $device->ip, $port;
          next;
      }

      my ($module) = split m/\./, $entry;
      push @portpower, {
          port   => $port,
          module => $module,
          admin  => $p_admin->{$entry},
          status => $p_pstatus->{$entry},
          class  => $p_class->{$entry},
          power  => $p_power->{$entry},

      };
      ++$seen_pp{$port};
  }

  schema('netdisco')->txn_do(sub {
    my $gone = $device->power_modules->delete;
    debug sprintf ' [%s] power - removed %d power modules',
      $device->ip, $gone;
    $device->power_modules->populate(\@devicepower);
    debug sprintf ' [%s] power - added %d new power modules',
      $device->ip, scalar @devicepower;
  });

  schema('netdisco')->txn_do(sub {
    my $gone = $device->powered_ports->delete;
    debug sprintf ' [%s] power - removed %d PoE capable ports',
      $device->ip, $gone;
    $device->powered_ports->populate(\@portpower);

    return Status->info(sprintf ' [%s] power - added %d new PoE capable ports',
      $device->ip, scalar @portpower);
  });
});

true;
