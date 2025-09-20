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
use App::Netdisco::DB::ExplicitLocking ':modes';

use Dancer::Plugin::DBIC 'schema';
use Scope::Guard 'guard';
use NetAddr::IP::Lite ':lower';
use Storable 'dclone';
use List::MoreUtils ();
use JSON::PP ();
use Encode;

register_worker({ phase => 'early', driver => 'snmp',
    title => 'basic device details (and creation)'}, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  # for field_protection
  my $orig_device = { $device->get_columns };

  # VTP Management Domain -- assume only one.
  my $vtpdomains = $snmp->vtp_d_name;
  if (defined $vtpdomains and scalar values %$vtpdomains) {
      $device->set_column( vtp_domain => (values %$vtpdomains)[-1] );
  }
  my $vtpmodes = $snmp->vtp_d_mode;
  if (defined $vtpmodes and scalar values %$vtpmodes) {
      $device->set_column( vtp_mode => (values %$vtpmodes)[-1] );
  }

  my $now = vars->{'timestamp'};
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
      my $val = $snmp->$property;
      $val = [values %$val]->[0] if ref $val eq 'HASH';
      $val = undef if $val and $val =~ m/^HASH\(/;
      $device->set_column( $property => $val );
  }

  my %utf8_properties = (
    qw( model    model
        serial   serial
        serial1  chassis_id
        contact  contact
        location location
    ),
  );

  foreach my $property (keys %utf8_properties) {
      my $val = $snmp->$property;
      $val = [values %$val]->[0] if ref $val eq 'HASH';
      ($val = Encode::decode('UTF-8', ($val || ''))) =~ s/\s+$//;
      $val = undef if $val and $val =~ m/^HASH\(/;
      $device->set_column( $utf8_properties{$property} => $val );
  }

  $device->set_column( num_ports  => ($snmp->ports || 0) );
  $device->set_column( snmp_class => $snmp->class );
  $device->set_column( snmp_engineid => unpack('H*', ($snmp->snmpEngineID || '')) );

  $device->set_column( last_discover => \$now );

  my $enterprises_mib = qr/(?:\.?1.3.6.1.4.1|enterprises)\.\d+/;
  my $try_vendor =
    ($device->model and $device->model =~ m/^${enterprises_mib}/) ? $device->model
    : ($device->vendor and $device->vendor =~ m/^${enterprises_mib}/) ? $device->vendor
    : ($device->id and $device->id =~ m/^${enterprises_mib}/) ? $device->id : undef;
  $try_vendor =~ s/^(?:\.?1.3.6.1.4.1|enterprises)// if $try_vendor;

  # fix up unknown vendor (enterprise number -> organization)
  if ($try_vendor and $try_vendor =~ m/^\.(\d+)/) {
      my $number = $1;
      debug sprintf ' searching for Enterprise Number "%s"', $number;
      my $ent = schema('netdisco')->resultset('Enterprise')->find($number);
      $device->set_column( vendor => $ent->organization ) if $ent;
  }

  # fix up unknown model using products OID cache
  if ($try_vendor) {
      my $oid = '.1.3.6.1.4.1' . $try_vendor;
      debug sprintf ' searching for Product ID "%s"', ('enterprises.' . $try_vendor);
      my $object = schema('netdisco')->resultset('Product')->find($oid);
      $device->set_column( model => $object->leaf ) if $object;
  }

  # protection for failed SNMP gather
  if (setting('enable_field_protection') and not $device->is_pseudo) {
      my $category = ($device->in_storage ? 'device' : 'new_device');
      my $protect = setting('field_protection')->{$category} || {};

      my %dirty = $device->get_dirty_columns;
      my $ip = $device->ip;
      foreach my $field (keys %$protect) {
          next if $device->in_storage and !exists $dirty{$field}; # field didn't change
          next unless acl_matches_only($ip, $protect->{$field});

          if ($field eq 'snmp_class') { # reject SNMP::Info (it would not be empty)
              return $job->cancel("discover cancelled: $ip returned unwanted class SNMP::Info")
                if $dirty{$field} eq 'SNMP::Info';
          }
          else {
              if (not $device->in_storage) { # new
                  return $job->cancel("discover cancelled: $ip failed to return valid $field")
                    if !defined $dirty{$field} or not length $dirty{$field};
              }
              elsif ($device->in_storage
                     and ($orig_device->{$field} or length $orig_device->{$field})) { # existing
                  return $job->cancel("rediscover cancelled: $ip failed to return valid $field")
                    if !defined $dirty{$field} or ($orig_device->{$field} and not $dirty{$field});
              }
          }
      }
  }

  # for existing device, filter custom_fields
  if ($device->in_storage) {
      my $coder = JSON::PP->new->utf8(0)->allow_nonref(1)->allow_unknown(1);

      # get the custom_fields
      my $fields = $coder->decode(Encode::encode('UTF-8',$device->custom_fields) || '{}');
      my %ok_fields = map {$_ => 1}
                      grep {defined}
                      map {$_->{name}}
                      @{ setting('custom_fields')->{device} || [] };

      # filter custom_fields for current valid fields
      foreach my $field (keys %ok_fields) {
          $ok_fields{$field} = exists $fields->{$field}
            ? Encode::decode('UTF-8', $fields->{$field}) : undef;
      }

      # set new custom_fields
      $device->set_column( custom_fields => $coder->encode(\%ok_fields) );
  }

  # support for Hooks
  vars->{'hook_data'} = { $device->get_columns };
  delete vars->{'hook_data'}->{'snmp_comm'}; # for privacy

  # support for new_device Hook
  vars->{'new_device'} = 1 if not $device->in_storage;

  schema('netdisco')->txn_do(sub {
    if ($device->serial and setting('delete_duplicate_serials')) {
        my $gone = schema('netdisco')->resultset('Device')->search({
          ip => { '!=' => $device->ip }, serial => $device->serial,
        })->delete;
        debug sprintf ' removed %s devices with the same serial number', ($gone || '0');
    }

    my $new = ($device->in_storage ? 'existing' : 'new');
    $device->update_or_insert(undef, {for => 'update'});
    return Status->done(sprintf 'Successful discover for %s device %s', $new, $device->ip);
  });
});

register_worker({ phase => 'early', driver => 'snmp',
    title => 'cancel if device canonical IP is known to another device'}, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  return unless $device->in_storage and vars->{'new_device'};

  my $db_device = get_device($device->ip);
  if ($device->ip ne $db_device->ip) {
    return schema('netdisco')->txn_do(sub {
      $device->delete;
      return $job->cancel("discover cancelled: $device already known as $db_device");
    });
  }

  return Status->info(" [$device] device - OK to continue discover (not a duplicate)");
});

register_worker({ phase => 'early', driver => 'snmp',
    title => 'cancel if no valid interfaces found'}, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  return unless $device->in_storage;

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  # clear the cached uptime and get a new one
  my $dev_uptime = ($device->is_pseudo ? $snmp->uptime : $snmp->load_uptime);
  if (!defined $dev_uptime) {
      return $job->cancel("discover cancelled: $device cannot report its uptime");
  }

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

register_worker({ phase => 'early', driver => 'snmp',
    title => 'get device IP aliases and their subnets'}, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  return unless $device->in_storage;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  my $now = vars->{'timestamp'};

  my @aliases = ();
  push @aliases, _get_ipv4_aliases($device, $snmp);
  push @aliases, _get_ipv6_aliases($device, $snmp);

  my @subnets = List::MoreUtils::uniq grep {defined} map {$_->{subnet}} @aliases;

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

    schema('netdisco')->resultset('Subnet')
      ->update_or_create({ net => $_, last_discover => \$now },
                         { for => 'update' }) for @subnets;

    return Status->info(sprintf ' [%s] aliases - added %d new aliases and %d subnets',
      $device->ip, scalar @aliases, scalar @subnets);
  });
});


# NOTE must come after the IP Aliases gathering for ignore ACLs to work
register_worker({ phase => 'early', driver => 'snmp',
    title => 'get port details'}, sub {
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
      return Status->info(sprintf ' [%s] interfaces - skipped, no uptime from device',
        $device->ip);
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

  # 981 must do this after filtering %deviceports to avoid weird data
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

  schema('netdisco')->resultset('DevicePort')->txn_do_locked(ACCESS_EXCLUSIVE, sub {
    my $coder = JSON::PP->new->utf8(0)->allow_nonref(1)->allow_unknown(1);

    # backup the custom_fields
    my %fields = map  {($_->{port} => $coder->decode(Encode::encode('UTF-8',$_->{custom_fields} || '{}')))}
                 grep {exists $deviceports{$_->{port}}}
                      $device->ports
                             ->search(undef, {columns => [qw/port custom_fields/]})
                             ->hri->all;

    my %ok_fields = map {$_ => 1}
                    grep {defined}
                    map {$_->{name}}
                    @{ setting('custom_fields')->{device_port} || [] };

    # filter custom_fields for current valid fields
    foreach my $port (keys %fields) {
        my %new_fields = ();

        foreach my $field (keys %ok_fields) {
            $new_fields{$field} = exists $fields{$port}->{$field}
              ? Encode::decode('UTF-8', $fields{$port}->{$field}) : undef;
        }

        # set new custom_fields
        $deviceports{$port}->{custom_fields} = $coder->encode(\%new_fields);
    }

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

      if (acl_matches($ip, 'group:__LOCAL_ADDRESSES__')) {
        debug sprintf
          ' [%s] device - skipping alias %s as potentially not unique',
          $device->ip, $addr;
        next;
      }

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
