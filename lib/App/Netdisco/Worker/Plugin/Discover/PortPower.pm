package App::Netdisco::Worker::Plugin::Discover::PortPower;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::SNMP qw/walk_mark incomplete_walks_for incomplete_walk_message
  incomplete_walk_level/;
use Dancer::Plugin::DBIC 'schema';

# an empty or absent module list on a complete walk means no PoE, so the stored
# modules go; the caller never reaches here after a cut-short walk
sub _store_device_power {
  my ($device, $p_watts, $p_status) = @_;
  my @devicepower = map {{
      ip     => $device->ip,
      module => $_,
      power  => $p_watts->{$_},
      status => $p_status->{$_},
  }} sort keys %{ $p_watts || {} };

  schema('netdisco')->txn_do(sub {
    my $rs = schema('netdisco')->resultset('DevicePower');
    $rs->upsert(\@devicepower) if scalar @devicepower;
    my $gone = $rs->remove_unseen({ ip => $device->ip },
      [ map {{ module => $_->{module} }} @devicepower ]);
    debug sprintf ' [%s] power - removed %d power modules',
      $device->ip, $gone;
    debug sprintf ' [%s] power - wrote %d power modules',
      $device->ip, scalar @devicepower;
  });
}

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  return unless $device->in_storage;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  my $walk_mark = walk_mark($snmp);
  my $p_watts  = $snmp->peth_power_watts;
  my $p_status = $snmp->peth_power_status;

  # a walk that was cut short must not look like a device with no PoE, so the
  # stored modules stand
  my @incomplete = incomplete_walks_for($device, $snmp, $walk_mark,
    qw/peth_power_watts peth_power_status/);
  my $skipped = '';
  my $level = incomplete_walk_level(@incomplete);
  if (scalar @incomplete) {
      $skipped = incomplete_walk_message($device, 'device_power', @incomplete);
      warning $skipped;
      return Status->$level($skipped) if !defined $p_watts;
  }
  elsif (!defined $p_watts) {
      _store_device_power($device, undef, undef);
      return Status->info(sprintf ' [%s] power - 0 power modules', $device->ip);
  }
  else {
      _store_device_power($device, $p_watts, $p_status);
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
    my $gone = $device->powered_ports->delete;
    debug sprintf ' [%s] power - removed %d PoE capable ports',
      $device->ip, $gone;
    $device->powered_ports->populate(\@portpower);

    return Status->$level(sprintf ' [%s] power - added %d new PoE capable ports%s',
      $device->ip, scalar @portpower, (length $skipped ? "; $skipped" : ''));
  });
});

true;
