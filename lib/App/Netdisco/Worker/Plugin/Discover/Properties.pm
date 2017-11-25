package App::Netdisco::Worker::Plugin::Discover::Properties;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Permission 'check_acl_no';
use App::Netdisco::Util::FastResolver 'hostnames_resolve_async';
use App::Netdisco::Util::DNS 'hostname_from_ip';
use Dancer::Plugin::DBIC 'schema';
use NetAddr::IP::Lite ':lower';
use Encode;

register_worker({ phase => 'early', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  my $ip_index   = $snmp->ip_index;
  my $interfaces = $snmp->interfaces;
  my $ip_netmask = $snmp->ip_netmask;

  # build device aliases suitable for DBIC
  my @aliases;
  foreach my $entry (keys %$ip_index) {
      my $ip = NetAddr::IP::Lite->new($entry)
        or next;
      my $addr = $ip->addr;

      next if $addr eq '0.0.0.0';
      next if check_acl_no($ip, 'group:__LOCAL_ADDRESSES__');
      next if setting('ignore_private_nets') and $ip->is_rfc1918;

      my $iid = $ip_index->{$addr};
      my $port = $interfaces->{$iid};
      my $subnet = $ip_netmask->{$addr}
        ? NetAddr::IP::Lite->new($addr, $ip_netmask->{$addr})->network->cidr
        : undef;

      debug sprintf ' [%s] device - aliased as %s', $device->ip, $addr;
      push @aliases, {
          alias => $addr,
          port => $port,
          subnet => $subnet,
          dns => undef,
      };
  }

  debug sprintf ' resolving %d aliases with max %d outstanding requests',
      scalar @aliases, $ENV{'PERL_ANYEVENT_MAX_OUTSTANDING_DNS'};
  my $resolved_aliases = hostnames_resolve_async(\@aliases);

  # fake one aliases entry for devices not providing ip_index
  push @$resolved_aliases, { alias => $device->ip, dns => $device->dns }
    if 0 == scalar @aliases;

  # VTP Management Domain -- assume only one.
  my $vtpdomains = $snmp->vtp_d_name;
  my $vtpdomain;
  if (defined $vtpdomains and scalar values %$vtpdomains) {
      $device->set_column( vtp_domain => (values %$vtpdomains)[-1] );
  }

  my $hostname = hostname_from_ip($device->ip);
  $device->set_column( dns => $hostname ) if $hostname;

  my @properties = qw/
    snmp_ver
    description uptime name
    layers ports mac
    ps1_type ps2_type ps1_status ps2_status
    fan slots
    vendor os os_ver
  /;

  foreach my $property (@properties) {
      $device->set_column( $property => $snmp->$property );
  }

  $device->set_column( model  => Encode::decode('UTF-8', $snmp->model)  );
  $device->set_column( serial => Encode::decode('UTF-8', $snmp->serial) );
  $device->set_column( contact => Encode::decode('UTF-8', $snmp->contact) );
  $device->set_column( location => Encode::decode('UTF-8', $snmp->location) );


  $device->set_column( snmp_class => $snmp->class );
  $device->set_column( last_discover => \'now()' );

  schema('netdisco')->txn_do(sub {
    my $gone = $device->device_ips->delete;
    debug sprintf ' [%s] device - removed %d aliases',
      $device->ip, $gone;
    $device->update_or_insert(undef, {for => 'update'});
    $device->device_ips->populate($resolved_aliases);
    debug sprintf ' [%s] device - added %d new aliases',
      $device->ip, scalar @aliases;
  });

  return Status->done("Ended discover for $device");
});

register_worker({ phase => 'early', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  return unless $device->in_storage;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  my $interfaces     = $snmp->interfaces;
  my $i_type         = $snmp->i_type;
  my $i_ignore       = $snmp->i_ignore;
  my $i_descr        = $snmp->i_description;
  my $i_mtu          = $snmp->i_mtu;
  my $i_speed        = $snmp->i_speed;
  my $i_mac          = $snmp->i_mac;
  my $i_up           = $snmp->i_up;
  my $i_up_admin     = $snmp->i_up_admin;
  my $i_name         = $snmp->i_name;
  my $i_duplex       = $snmp->i_duplex;
  my $i_duplex_admin = $snmp->i_duplex_admin;
  my $i_stp_state    = $snmp->i_stp_state;
  my $i_vlan         = $snmp->i_vlan;
  my $i_lastchange   = $snmp->i_lastchange;
  my $agg_ports      = $snmp->agg_ports;

  # clear the cached uptime and get a new one
  my $dev_uptime = $snmp->load_uptime;
  if (!defined $dev_uptime) {
      error sprintf ' [%s] interfaces - Error! Failed to get uptime from device!',
        $device->ip;
      return Status->error("discover failed: no uptime from device $device!");
  }

  # used to track how many times the device uptime wrapped
  my $dev_uptime_wrapped = 0;

  # use SNMP-FRAMEWORK-MIB::snmpEngineTime if available to
  # fix device uptime if wrapped
  if (defined $snmp->snmpEngineTime) {
      $dev_uptime_wrapped = int( $snmp->snmpEngineTime * 100 / 2**32 );
      if ($dev_uptime_wrapped > 0) {
          info sprintf ' [%s] interface - device uptime wrapped %d times - correcting',
            $device->ip, $dev_uptime_wrapped;
          $device->uptime( $dev_uptime + $dev_uptime_wrapped * 2**32 );
      }
  }

  # build device interfaces suitable for DBIC
  my %interfaces;
  foreach my $entry (keys %$interfaces) {
      my $port = $interfaces->{$entry};

      if (not $port) {
          debug sprintf ' [%s] interfaces - ignoring %s (no port mapping)',
            $device->ip, $entry;
          next;
      }

      if (scalar grep {$port =~ m/^$_$/} @{setting('ignore_interfaces') || []}) {
          debug sprintf
            ' [%s] interfaces - ignoring %s (%s) (config:ignore_interfaces)',
            $device->ip, $entry, $port;
          next;
      }

      if (exists $i_ignore->{$entry}) {
          debug sprintf ' [%s] interfaces - ignoring %s (%s) (%s)',
            $device->ip, $entry, $port, $i_type->{$entry};
          next;
      }

      my $lc = $i_lastchange->{$entry} || 0;
      if (not $dev_uptime_wrapped and $lc > $dev_uptime) {
          info sprintf ' [%s] interfaces - device uptime wrapped (%s) - correcting',
            $device->ip, $port;
          $device->uptime( $dev_uptime + 2**32 );
          $dev_uptime_wrapped = 1;
      }

      if ($device->is_column_changed('uptime') and $lc) {
          if ($lc < $dev_uptime) {
              # ambiguous: lastchange could be sysUptime before or after wrap
              if ($dev_uptime > 30000 and $lc < 30000) {
                  # uptime wrap more than 5min ago but lastchange within 5min
                  # assume lastchange was directly after boot -> no action
              }
              else {
                  # uptime wrap less than 5min ago or lastchange > 5min ago
                  # to be on safe side, assume lastchange after counter wrap
                  debug sprintf
                    ' [%s] interfaces - correcting LastChange for %s, assuming sysUptime wrap',
                    $device->ip, $port;
                  $lc += $dev_uptime_wrapped * 2**32;
              }
          }
      }

      $interfaces{$port} = {
          port         => $port,
          descr        => $i_descr->{$entry},
          up           => $i_up->{$entry},
          up_admin     => $i_up_admin->{$entry},
          mac          => $i_mac->{$entry},
          speed        => $i_speed->{$entry},
          mtu          => $i_mtu->{$entry},
          name         => Encode::decode('UTF-8', $i_name->{$entry}),
          duplex       => $i_duplex->{$entry},
          duplex_admin => $i_duplex_admin->{$entry},
          stp          => $i_stp_state->{$entry},
          type         => $i_type->{$entry},
          vlan         => $i_vlan->{$entry},
          pvid         => $i_vlan->{$entry},
          is_master    => 'false',
          slave_of     => undef,
          lastchange   => $lc,
      };
  }

  # must do this after building %interfaces so that we can set is_master
  foreach my $sidx (keys %$agg_ports) {
      my $slave  = $interfaces->{$sidx} or next;
      my $master = $interfaces->{ $agg_ports->{$sidx} } or next;
      next unless exists $interfaces{$slave} and exists $interfaces{$master};

      $interfaces{$slave}->{slave_of} = $master;
      $interfaces{$master}->{is_master} = 'true';
  }

  schema('netdisco')->resultset('DevicePort')->txn_do_locked(sub {
    my $gone = $device->ports->delete({keep_nodes => 1});
    debug sprintf ' [%s] interfaces - removed %d interfaces',
      $device->ip, $gone;
    $device->update_or_insert(undef, {for => 'update'});
    $device->ports->populate([values %interfaces]);

    return Status->info(sprintf ' [%s] interfaces - added %d new interfaces',
      $device->ip, scalar values %interfaces);
  });
});

true;
