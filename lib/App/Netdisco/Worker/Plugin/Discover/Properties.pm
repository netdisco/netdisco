package App::Netdisco::Worker::Plugin::Discover::Properties;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Permission qw/acl_matches acl_matches_only/;
use App::Netdisco::Util::FastResolver 'hostnames_resolve_async';
use App::Netdisco::Util::Device 'get_device';
use App::Netdisco::Util::DNS 'hostname_from_ip';
use App::Netdisco::Util::SNMP 'snmp_comm_reindex';
use App::Netdisco::Util::Web 'sort_port';
use Dancer::Plugin::DBIC 'schema';
use Scope::Guard 'guard';
use NetAddr::IP::Lite ':lower';
use Storable 'dclone';
use Encode;

register_worker({ phase => 'early', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

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
    layers mac
    ps1_type ps2_type ps1_status ps2_status
    fan slots
    vendor os os_ver
  /;

  foreach my $property (@properties) {
      $device->set_column( $property => $snmp->$property );
  }

  (my $model  = Encode::decode('UTF-8', ($snmp->model  || ''))) =~ s/\s+$//;
  (my $serial = Encode::decode('UTF-8', ($snmp->serial || ''))) =~ s/\s+$//;
  (my $chassis_id = Encode::decode('UTF-8', ($snmp->serial1 || ''))) =~ s/\s+$//;
  $device->set_column( model  => $model  );
  $device->set_column( serial => $serial );
  $device->set_column( chassis_id => (($chassis_id ne $serial) ? $chassis_id : '') );
  $device->set_column( contact => Encode::decode('UTF-8', $snmp->contact) );
  $device->set_column( location => Encode::decode('UTF-8', $snmp->location) );

  $device->set_column( num_ports  => ($snmp->ports || 0) );
  $device->set_column( snmp_class => $snmp->class );
  $device->set_column( snmp_engineid => unpack('H*', ($snmp->snmpEngineID || '')) );

  $device->set_column( last_discover => \'LOCALTIMESTAMP' );

  # protection for failed SNMP gather
  if ($device->in_storage and not $device->is_pseudo) {
      my $ip = $device->ip;
      my $protect = setting('snmp_field_protection')->{'device'} || {};
      my %dirty = $device->get_dirty_columns;
      foreach my $field (keys %dirty) {
          next unless acl_matches_only($ip, $protect->{$field});
          if (!defined $dirty{$field} or $dirty{$field} eq '') {
              return $job->cancel("discover cancelled: $ip failed to return valid $field");
          }
      }
  }

  # support for Hooks
  vars->{'hook_data'} = { $device->get_columns };
  delete vars->{'hook_data'}->{'snmp_comm'}; # for privacy

  # support for new_device Hook
  vars->{'new_device'} = 1 if not $device->in_storage;

  schema('netdisco')->txn_do(sub {
    $device->update_or_insert(undef, {for => 'update'});
    return Status->done("Ended discover for $device");
  });
});

register_worker({ phase => 'early', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  return unless $device->in_storage;
  return unless $job->subaction eq 'with-nodes';

  my $db_device = get_device($device->ip);
  if ($device->ip ne $db_device->ip) {
    return schema('netdisco')->txn_do(sub {
      $device->delete;
      return $job->cancel("fresh discover cancelled: $device already known as $db_device");
    });
  }

  return Status->info(" [$device] device - OK to continue discover (not a duplicate)");
});

register_worker({ phase => 'early', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  return unless $device->in_storage;

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  my $pass = Status->info(" [$device] device - OK to continue discover (valid interfaces)");
  my $interfaces = $snmp->interfaces;

  # OK if no interfaces
  return $pass if 0 == scalar keys %$interfaces;
  # OK if any value is not the same as key
  return $pass if scalar grep {$_ ne $interfaces->{$_}} keys %$interfaces;
  # OK if any non-digit in values
  return $pass if scalar grep {$_ !~ m/^[0-9]+$/} values %$interfaces;

  # gather ports
  my $device_ports = {map {($_->port => $_)}
                          $device->ports(undef, {prefetch => 'properties'})->all};
  # OK if no ports
  return $pass if 0 == scalar keys %$device_ports;
  # OK if any interface value is a port name
  foreach my $port (keys %$device_ports) {
      return $pass if scalar grep {$port eq $_} values %$interfaces;
  }

  # else cancel
  return $job->cancel("discover cancelled: $device failed to return valid interfaces");
});

register_worker({ phase => 'early', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  return unless $device->in_storage;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  my @aliases = ();
  push @aliases, _get_ipv4_aliases($device, $snmp);
  push @aliases, _get_ipv6_aliases($device, $snmp);

  debug sprintf ' resolving %d aliases with max %d outstanding requests',
      scalar @aliases, $ENV{'PERL_ANYEVENT_MAX_OUTSTANDING_DNS'};
  my $resolved_aliases = hostnames_resolve_async(\@aliases);

  # fake one aliases entry for devices not providing ip_index
  # or if we're discovering on an IP not listed in ip_index
  push @$resolved_aliases, { alias => $device->ip, dns => $device->dns }
    if 0 == scalar grep {$_->{alias} eq $device->ip} @aliases;

  # support for Hooks
  vars->{'hook_data'}->{'device_ips'} = $resolved_aliases;

  schema('netdisco')->txn_do(sub {
    my $gone = $device->device_ips->delete;
    debug sprintf ' [%s] device - removed %d aliases',
      $device->ip, $gone;
    $device->device_ips->populate($resolved_aliases);

    return Status->info(sprintf ' [%s] aliases - added %d new aliases',
      $device->ip, scalar @aliases);
  });
});


# NOTE must come after the IP Aliases gathering for ignore ACLs to work
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
  my $i_speed_admin  = $snmp->i_speed_admin;
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
  my $i_subs         = $snmp->i_subinterfaces;

  # clear the cached uptime and get a new one
  my $dev_uptime = ($device->is_pseudo ? $snmp->uptime : $snmp->load_uptime);
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
          debug sprintf ' [%s] interfaces - device uptime wrapped %d times - correcting',
            $device->ip, $dev_uptime_wrapped;
          $device->uptime( $dev_uptime + $dev_uptime_wrapped * 2**32 );
      }
  }

  # build device interfaces suitable for DBIC
  my %deviceports;
  PORT: foreach my $entry (keys %$interfaces) {
      my $port = $interfaces->{$entry};

      if (not $port) {
          debug sprintf ' [%s] interfaces - ignoring %s (no port mapping)',
            $device->ip, $entry;
          next PORT;
      }

      if (exists $i_ignore->{$entry}) {
          debug sprintf ' [%s] interfaces - ignoring %s (%s) (%s) (SNMP::Info::i_ignore)',
            $device->ip, $entry, $port, ($i_type->{$entry} || '');
          next PORT;
      }

      # create a DBIx::Class row for this port which can be used to test ACLs
      # also include the Device IP alias if we have one for L3 interfaces
      $deviceports{$port} = {
          port         => $port,
          descr        => $i_descr->{$entry},
          up           => $i_up->{$entry},
          up_admin     => $i_up_admin->{$entry},
          mac          => $i_mac->{$entry},
          speed        => $i_speed->{$entry},
          speed_admin  => $i_speed_admin->{$entry},
          mtu          => $i_mtu->{$entry},
          name         => Encode::decode('UTF-8', $i_name->{$entry}),
          duplex       => $i_duplex->{$entry},
          duplex_admin => $i_duplex_admin->{$entry},
          stp          => $i_stp_state->{$entry},
          type         => $i_type->{$entry},
          vlan         => $i_vlan->{$entry},
          pvid         => $i_vlan->{$entry},
          has_subinterfaces => 'false',
          is_master         => 'false',
          slave_of          => undef,
      };
  }

  if (scalar @{ setting('ignore_deviceports') }) {
    my $port_map = {};

    map { push @{ $port_map->{ $_->port } }, $_ }
        grep { $_->port }
        $device->device_ips()->all;

    map { push @{ $port_map->{ $_->{port} } }, $_ }
        values %{ dclone (\%deviceports || {}) };

    foreach my $map (@{ setting('ignore_deviceports')}) {
        next unless ref {} eq ref $map;

        foreach my $key (sort keys %$map) {
            # lhs matches device, rhs matches port
            next unless $key and $map->{$key};
            next unless acl_matches($device, $key);

            foreach my $port (sort { sort_port( $a, $b) } keys %$port_map) {
                next unless acl_matches($port_map->{$port}, $map->{$key});

                debug sprintf ' [%s] interfaces - ignoring %s (config:ignore_deviceports)',
                  $device->ip, $port;
                delete $deviceports{$port};
            }
        }
    }
  }

  # #981 must do this after filtering %deviceports to avoid weird data
  UPTIME: foreach my $entry (sort keys %$interfaces) {
      my $port = $interfaces->{$entry};
      next unless exists $deviceports{$port};
      my $lc = $i_lastchange->{$entry} || 0;

      # allow three minutes skew during boot, in case lc is larger than uptime
      # because of different counters starting at different times
      if (not $dev_uptime_wrapped and $lc > ($dev_uptime + 18000)) {
          debug sprintf ' [%s] interfaces - device uptime wrapped (%s) - correcting',
            $device->ip, $port;
          $device->uptime( $dev_uptime + 2**32 );
          $dev_uptime_wrapped = 1;
      }

      if ($device->is_column_changed('uptime') and $lc and $lc < $dev_uptime) {
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

      $deviceports{$port}->{lastchange} = $lc;
  }

  # must do this after building %deviceports so that we can set is_master
  foreach my $sidx (keys %$agg_ports) {
      my $slave  = $interfaces->{$sidx} or next;
      next unless defined $agg_ports->{$sidx}; # slave without a master?!
      my $master = $interfaces->{ $agg_ports->{$sidx} } or next;
      next unless exists $deviceports{$slave} and exists $deviceports{$master};

      $deviceports{$slave}->{slave_of} = $master;
      $deviceports{$master}->{is_master} = 'true';
  }

  # also for VLAN subinterfaces
  foreach my $pidx (keys %$i_subs) {
      my $parent = $interfaces->{$pidx} or next;
      # parent without subinterfaces?
      next unless defined $i_subs->{$pidx}
       and ref [] eq ref $i_subs->{$pidx}
       and scalar @{ $i_subs->{$pidx} }
       and exists $deviceports{$parent};

      $deviceports{$parent}->{has_subinterfaces} = 'true';
      foreach my $sidx (@{ $i_subs->{$pidx} }) {
          my $sub = $interfaces->{$sidx} or next;
          next unless exists $deviceports{$sub};
          $deviceports{$sub}->{slave_of} = $parent;
      }
  }

  # update num_ports
  $device->num_ports( scalar values %deviceports );

  # support for Hooks
  vars->{'hook_data'}->{'ports'} = [values %deviceports];

  schema('netdisco')->resultset('DevicePort')->txn_do_locked(sub {
    # backup the custom_fields
    my @fields = grep {exists $deviceports{$_->{port}}} $device->ports
      ->search(undef, {columns => [qw/port custom_fields/]})->hri->all;
    $deviceports{$_->{port}}->{custom_fields} = $_->{custom_fields}
      for @fields;

    my $gone = $device->ports->delete({keep_nodes => 1});
    debug sprintf ' [%s] interfaces - removed %d interfaces',
      $device->ip, $gone;

    # uptime and num_ports changed
    $device->update();

    $device->ports->populate([values %deviceports]);

    return Status->info(sprintf ' [%s] interfaces - added %d new interfaces',
      $device->ip, scalar values %deviceports);
  });
});

# return a list of VRF which are OK to connect
sub _get_vrf_list {
    my ($device, $snmp) = @_;

    return () if ! $snmp->cisco_comm_indexing;

    my @ok_vrfs = ();
    my $vrf_name = $snmp->vrf_name || {};

    while (my ($idx, $vrf) = each(%$vrf_name)) {
        if ($vrf =~ /^\S+$/) {
            my $ctx_name = pack("C*",split(/\./,$idx));
            $ctx_name =~ s/.*[^[:print:]]+//;
            debug sprintf(' [%s] Discover VRF %s with SNMP Context %s', $device->ip, $vrf, $ctx_name);
            push (@ok_vrfs, $ctx_name);
        }
    }

    return @ok_vrfs;
}

sub _get_ipv4_aliases {
  my ($device, $snmp) = @_;
  my @aliases;

  my $ip_index   = $snmp->ip_index;
  my $ip_table   = $snmp->ip_table;
  my $interfaces = $snmp->interfaces;
  my $ip_netmask = $snmp->ip_netmask;

  # Get IP Table per VRF if supported
  my @vrf_list = _get_vrf_list($device, $snmp);
  if (scalar @vrf_list) {
    my $guard = guard { snmp_comm_reindex($snmp, $device, 0) };
    foreach my $vrf (@vrf_list) {
      snmp_comm_reindex($snmp, $device, $vrf);
      $ip_index   = { %$ip_index,   %{$snmp->ip_index}   };
      $ip_table   = { %$ip_table,   %{$snmp->ip_table}   };
      $interfaces = { %$interfaces, %{$snmp->interfaces} };
      $ip_netmask = { %$ip_netmask, %{$snmp->ip_netmask} };
    }
  }

  # build device aliases suitable for DBIC
  foreach my $entry (keys %$ip_index) {
      my $ip = NetAddr::IP::Lite->new($ip_table->{$entry}) || NetAddr::IP::Lite->new($entry)
        or next;
      my $addr = $ip->addr;

      next if $addr eq '0.0.0.0';
      next if acl_matches($ip, 'group:__LOOPBACK_ADDRESSES__');
      next if setting('ignore_private_nets') and $ip->is_rfc1918;

      my $iid = $ip_index->{$entry};
      my $port = $interfaces->{$iid};
      my $subnet = $ip_netmask->{$entry}
        ? NetAddr::IP::Lite->new($addr, $ip_netmask->{$entry})->network->cidr
        : undef;

      debug sprintf ' [%s] device - aliased as %s', $device->ip, $addr;
      push @aliases, {
          alias => $addr,
          port => $port,
          subnet => $subnet,
          dns => undef,
      };
  }

  return @aliases;
}

sub _get_ipv6_aliases {
  my ($device, $snmp) = @_;
  my @aliases;

  my $ipv6_index  = $snmp->ipv6_index || {};
  my $ipv6_addr   = $snmp->ipv6_addr || {};
  my $ipv6_type   = $snmp->ipv6_type || {};
  my $ipv6_pfxlen = $snmp->ipv6_addr_prefixlength || {};
  my $interfaces  = $snmp->interfaces || {};

  # Get IP Table per VRF if supported
  my @vrf_list = _get_vrf_list($device, $snmp);
  if (scalar @vrf_list) {
    my $guard = guard { snmp_comm_reindex($snmp, $device, 0) };
    foreach my $vrf (@vrf_list) {
      snmp_comm_reindex($snmp, $device, $vrf);
      $ipv6_index  = { %$ipv6_index,  %{$snmp->ipv6_index || {}} };
      $ipv6_addr   = { %$ipv6_addr,   %{$snmp->ipv6_addr || {}} };
      $ipv6_type   = { %$ipv6_type,   %{$snmp->ipv6_type || {}} };
      $ipv6_pfxlen = { %$ipv6_pfxlen, %{$snmp->ipv6_addr_prefixlength || {}} };
      $interfaces  = { %$interfaces,  %{$snmp->interfaces} };
    }
  }

  # build device aliases suitable for DBIC
  foreach my $iid (keys %$ipv6_index) {
      next unless $ipv6_type->{$iid} and $ipv6_type->{$iid} eq 'unicast';
      my $entry = $ipv6_addr->{$iid} or next;
      my $ip = NetAddr::IP::Lite->new($entry) or next;
      my $addr = $ip->addr;

      next if $addr eq '::0';
      next if acl_matches($ip, 'group:__LOOPBACK_ADDRESSES__');

      my $port   = $interfaces->{ $ipv6_index->{$iid} };
      my $subnet = $ipv6_pfxlen->{$iid}
        ? NetAddr::IP::Lite->new($addr .'/'. $ipv6_pfxlen->{$iid})->network->cidr
        : undef;

      debug sprintf ' [%s] device - aliased as %s', $device->ip, $addr;
      push @aliases, {
          alias => $addr,
          port => $port,
          subnet => $subnet,
          dns => undef,
      };
  }

  return @aliases;
}

true;
