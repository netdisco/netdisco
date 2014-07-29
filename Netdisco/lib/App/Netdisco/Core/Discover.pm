package App::Netdisco::Core::Discover;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::Device qw/get_device is_discoverable/;
use App::Netdisco::Util::DNS ':all';
use App::Netdisco::JobQueue qw/jq_queued jq_insert/;
use NetAddr::IP::Lite ':lower';
use List::MoreUtils ();
use Encode;
use Try::Tiny;
use Net::MAC;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  set_canonical_ip
  store_device store_interfaces store_wireless
  store_vlans store_power store_modules
  store_neighbors discover_new_neighbors
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Core::Discover

=head1 DESCRIPTION

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 set_canonical_ip( $device, $snmp )

Returns: C<$device>

Given a Device database object, and a working SNMP connection, check whether
the database object's IP is the best choice for that device. If not, return
a new Device database object with the canonical IP.

The Device database object can be a fresh L<DBIx::Class::Row> object which is
not yet stored to the database.

=cut

sub set_canonical_ip {
  my ($device, $snmp) = @_;

  my $oldip = $device->ip;
  my $newip = $snmp->root_ip;

  if (defined $newip) {
      if ($oldip ne $newip) {
          debug sprintf ' [%s] device - changing root IP to alt IP %s',
            $oldip, $newip;

          schema('netdisco')->txn_do(sub {
            if ($device->in_storage) {
                # remove old device and aliases
                my $copy = schema('netdisco')->resultset('Device')
                  ->find({ip => $oldip});

                schema('netdisco')->resultset('Device')
                  ->search({ ip => $device->ip })->delete({keep_nodes => 1});
                debug sprintf ' [%s] device - deleted self', $oldip;

                $device = schema('netdisco')->resultset('Device')
                  ->create({ $copy->get_columns, ip => $newip });

                # make nodes follow device
                schema('netdisco')->resultset('Node')
                  ->search({switch => $oldip})
                  ->update({switch => $newip});
            }
            else {
                $device->set_column(ip => $newip);
            }
          });
      }
  }
  else {
      my $revname = ipv4_from_hostname($snmp->name);
      if (setting('reverse_sysname') and $revname) {
          debug sprintf ' [%s] device - changing root IP to revname %s',
            $oldip, $revname;
          $device->ip($revname);
      }
  }

  # either root_ip is changed or unchanged, but it exists
  return $device;
}

=head2 store_device( $device, $snmp )

Given a Device database object, and a working SNMP connection, discover and
store basic device information.

The Device database object can be a fresh L<DBIx::Class::Row> object which is
not yet stored to the database.

=cut

sub store_device {
  my ($device, $snmp) = @_;

  my $ip_index   = $snmp->ip_index;
  my $interfaces = $snmp->interfaces;
  my $ip_netmask = $snmp->ip_netmask;

  my $hostname = hostname_from_ip($device->ip);
  $device->dns($hostname) if $hostname;
  my $localnet = NetAddr::IP::Lite->new('127.0.0.0/8');

  # build device aliases suitable for DBIC
  my @aliases;
  foreach my $entry (keys %$ip_index) {
      my $ip = NetAddr::IP::Lite->new($entry);
      my $addr = $ip->addr;

      next if $addr eq '0.0.0.0';
      next if $ip->within($localnet);
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
  push @$resolved_aliases, { alias => $device->ip, dns => $hostname }
    if 0 == scalar @aliases;

  # VTP Management Domain -- assume only one.
  my $vtpdomains = $snmp->vtp_d_name;
  my $vtpdomain;
  if (defined $vtpdomains and scalar values %$vtpdomains) {
      $device->vtp_domain( (values %$vtpdomains)[-1] );
  }

  my @properties = qw/
    snmp_ver
    description uptime contact name location
    layers ports mac
    ps1_type ps2_type ps1_status ps2_status
    fan slots
    vendor os os_ver
  /;

  foreach my $property (@properties) {
      $device->$property( $snmp->$property );
  }

  $device->model(  Encode::decode('UTF-8', $snmp->model)  );
  $device->serial( Encode::decode('UTF-8', $snmp->serial) );

  $device->snmp_class( $snmp->class );
  $device->last_discover(\'now()');

  schema('netdisco')->txn_do(sub {
    my $gone = $device->device_ips->delete;
    debug sprintf ' [%s] device - removed %d aliases',
      $device->ip, $gone;
    $device->update_or_insert(undef, {for => 'update'});
    $device->device_ips->populate($resolved_aliases);
    debug sprintf ' [%s] device - added %d new aliases',
      $device->ip, scalar @aliases;
  });
}

=head2 store_interfaces( $device, $snmp )

Given a Device database object, and a working SNMP connection, discover and
store the device's interface/port information.

The Device database object can be a fresh L<DBIx::Class::Row> object which is
not yet stored to the database.

=cut

sub store_interfaces {
  my ($device, $snmp) = @_;

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
          name         => $i_name->{$entry},
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
    debug sprintf ' [%s] interfaces - added %d new interfaces',
      $device->ip, scalar values %interfaces;
  });
}

=head2 store_wireless( $device, $snmp )

Given a Device database object, and a working SNMP connection, discover and
store the device's wireless interface information.

The Device database object can be a fresh L<DBIx::Class::Row> object which is
not yet stored to the database.

=cut

sub store_wireless {
  my ($device, $snmp) = @_;

  my $ssidlist = $snmp->i_ssidlist;
  return unless scalar keys %$ssidlist;

  my $interfaces = $snmp->interfaces;
  my $ssidbcast  = $snmp->i_ssidbcast;
  my $ssidmac    = $snmp->i_ssidmac;
  my $channel    = $snmp->i_80211channel;
  my $power      = $snmp->dot11_cur_tx_pwr_mw;

  # build device ssid list suitable for DBIC
  my @ssids;
  foreach my $entry (keys %$ssidlist) {
      (my $iid = $entry) =~ s/\.\d+$//;
      my $port = $interfaces->{$iid};

      if (not $port) {
          debug sprintf ' [%s] wireless - ignoring %s (no port mapping)',
            $device->ip, $iid;
          next;
      }

      push @ssids, {
          port      => $port,
          ssid      => $ssidlist->{$entry},
          broadcast => $ssidbcast->{$entry},
          bssid     => $ssidmac->{$entry},
      };
  }

  schema('netdisco')->txn_do(sub {
    my $gone = $device->ssids->delete;
    debug sprintf ' [%s] wireless - removed %d SSIDs',
      $device->ip, $gone;
    $device->ssids->populate(\@ssids);
    debug sprintf ' [%s] wireless - added %d new SSIDs',
      $device->ip, scalar @ssids;
  });

  # build device channel list suitable for DBIC
  my @channels;
  foreach my $entry (keys %$channel) {
      my $port = $interfaces->{$entry};

      if (not $port) {
          debug sprintf ' [%s] wireless - ignoring %s (no port mapping)',
            $device->ip, $entry;
          next;
      }

      push @channels, {
          port    => $port,
          channel => $channel->{$entry},
          power   => $power->{$entry},
      };
  }

  schema('netdisco')->txn_do(sub {
    my $gone = $device->wireless_ports->delete;
    debug sprintf ' [%s] wireless - removed %d wireless channels',
      $device->ip, $gone;
    $device->wireless_ports->populate(\@channels);
    debug sprintf ' [%s] wireless - added %d new wireless channels',
      $device->ip, scalar @channels;
  });
}

=head2 store_vlans( $device, $snmp )

Given a Device database object, and a working SNMP connection, discover and
store the device's vlan information.

The Device database object can be a fresh L<DBIx::Class::Row> object which is
not yet stored to the database.

=cut

sub store_vlans {
  my ($device, $snmp) = @_;

  my $v_name  = $snmp->v_name;
  my $v_index = $snmp->v_index;

  # build device vlans suitable for DBIC
  my %v_seen = ();
  my @devicevlans;
  foreach my $entry (keys %$v_name) {
      my $vlan = $v_index->{$entry};
      ++$v_seen{$vlan};

      push @devicevlans, {
          vlan => $vlan,
          description => $v_name->{$entry},
          last_discover => \'now()',
      };
  }

  my $i_vlan            = $snmp->i_vlan;
  my $i_vlan_membership = $snmp->i_vlan_membership;
  my $i_vlan_type       = $snmp->i_vlan_type;
  my $interfaces        = $snmp->interfaces;

  # build device port vlans suitable for DBIC
  my @portvlans;
  foreach my $entry (keys %$i_vlan_membership) {
      my $port = $interfaces->{$entry};
      next unless defined $port;

      my $type = $i_vlan_type->{$entry};

      foreach my $vlan (@{ $i_vlan_membership->{$entry} }) {
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
    debug sprintf ' [%s] vlans - added %d new port VLANs',
      $device->ip, scalar @portvlans;
  });
}

=head2 store_power( $device, $snmp )

Given a Device database object, and a working SNMP connection, discover and
store the device's PoE information.

The Device database object can be a fresh L<DBIx::Class::Row> object which is
not yet stored to the database.

=cut

sub store_power {
  my ($device, $snmp) = @_;

  my $p_watts  = $snmp->peth_power_watts;
  my $p_status = $snmp->peth_power_status;

  if (!defined $p_watts) {
      debug sprintf ' [%s] power - 0 power modules', $device->ip;
      return;
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

  my $interfaces = $snmp->interfaces;
  my $p_ifindex  = $snmp->peth_port_ifindex;
  my $p_admin    = $snmp->peth_port_admin;
  my $p_pstatus  = $snmp->peth_port_status;
  my $p_class    = $snmp->peth_port_class;
  my $p_power    = $snmp->peth_port_power;

  # build device port power info suitable for DBIC
  my @portpower;
  foreach my $entry (keys %$p_ifindex) {
      my $port = $interfaces->{ $p_ifindex->{$entry} };
      next unless $port;

      my ($module) = split m/\./, $entry;

      push @portpower, {
          port   => $port,
          module => $module,
          admin  => $p_admin->{$entry},
          status => $p_pstatus->{$entry},
          class  => $p_class->{$entry},
          power  => $p_power->{$entry},

      };
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
    debug sprintf ' [%s] power - added %d new PoE capable ports',
      $device->ip, scalar @portpower;
  });
}

=head2 store_modules( $device, $snmp )

Given a Device database object, and a working SNMP connection, discover and
store the device's module information.

The Device database object can be a fresh L<DBIx::Class::Row> object which is
not yet stored to the database.

=cut

sub store_modules {
  my ($device, $snmp) = @_;

  my $e_index  = $snmp->e_index;

  if (!defined $e_index) {
      debug sprintf ' [%s] modules - 0 chassis components', $device->ip;
      return;
  }

  my $e_descr   = $snmp->e_descr;
  my $e_type    = $snmp->e_type;
  my $e_parent  = $snmp->e_parent;
  my $e_name    = $snmp->e_name;
  my $e_class   = $snmp->e_class;
  my $e_pos     = $snmp->e_pos;
  my $e_hwver   = $snmp->e_hwver;
  my $e_fwver   = $snmp->e_fwver;
  my $e_swver   = $snmp->e_swver;
  my $e_model   = $snmp->e_model;
  my $e_serial  = $snmp->e_serial;
  my $e_fru     = $snmp->e_fru;

  # build device modules list for DBIC
  my @modules;
  foreach my $entry (keys %$e_index) {
      push @modules, {
          index  => $e_index->{$entry},
          type   => $e_type->{$entry},
          parent => $e_parent->{$entry},
          name   => Encode::decode('UTF-8', $e_name->{$entry}),
          class  => $e_class->{$entry},
          pos    => $e_pos->{$entry},
          hw_ver => Encode::decode('UTF-8', $e_hwver->{$entry}),
          fw_ver => Encode::decode('UTF-8', $e_fwver->{$entry}),
          sw_ver => Encode::decode('UTF-8', $e_swver->{$entry}),
          model  => Encode::decode('UTF-8', $e_model->{$entry}),
          serial => Encode::decode('UTF-8', $e_serial->{$entry}),
          fru    => $e_fru->{$entry},
          description => Encode::decode('UTF-8', $e_descr->{$entry}),
          last_discover => \'now()',
      };
  }

  schema('netdisco')->txn_do(sub {
    my $gone = $device->modules->delete;
    debug sprintf ' [%s] modules - removed %d chassis modules',
      $device->ip, $gone;
    $device->modules->populate(\@modules);
    debug sprintf ' [%s] modules - added %d new chassis modules',
      $device->ip, scalar @modules;
  });
}

=head2 store_neighbors( $device, $snmp )

returns: C<@to_discover>

Given a Device database object, and a working SNMP connection, discover and
store the device's port neighbors information.

Entries in the Topology database table will override any discovered device
port relationships.

The Device database object can be a fresh L<DBIx::Class::Row> object which is
not yet stored to the database.

A list of discovererd neighbors will be returned as [C<$ip>, C<$type>] tuples.

=cut

sub store_neighbors {
  my ($device, $snmp) = @_;
  my @to_discover = ();

  # first allow any manually configured topology to be set
  _set_manual_topology($device, $snmp);

  my $c_ip = $snmp->c_ip;
  unless ($snmp->hasCDP or scalar keys %$c_ip) {
      debug sprintf ' [%s] neigh - CDP/LLDP not enabled!', $device->ip;
      return @to_discover;
  }

  my $interfaces = $snmp->interfaces;
  my $c_if       = $snmp->c_if;
  my $c_port     = $snmp->c_port;
  my $c_id       = $snmp->c_id;
  my $c_platform = $snmp->c_platform;
  my $c_cap      = $snmp->c_cap;

  foreach my $entry (List::MoreUtils::uniq( (keys %$c_ip), (keys %$c_cap) )) {
      if (!defined $c_if->{$entry} or !defined $interfaces->{ $c_if->{$entry} }) {
          debug sprintf ' [%s] neigh - port for IID:%s not resolved, skipping',
            $device->ip, $entry;
          next;
      }

      my $port = $interfaces->{ $c_if->{$entry} };
      my $portrow = schema('netdisco')->resultset('DevicePort')
          ->single({ip => $device->ip, port => $port});

      if (!defined $portrow) {
          info sprintf ' [%s] neigh - local port %s not in database!',
            $device->ip, $port;
          next;
      }

      my $remote_ip   = $c_ip->{$entry};
      my $remote_ipad = NetAddr::IP::Lite->new($remote_ip);
      my $remote_port = undef;
      my $remote_type = Encode::decode('UTF-8', $c_platform->{$entry} || '');
      my $remote_id   = Encode::decode('UTF-8', $c_id->{$entry});
      my $remote_cap  = $c_cap->{$entry} || [];

      # IP Phone and WAP detection type fixup
      if (scalar @$remote_cap or $remote_type) {
          my $phone_flag = grep {/phone/i} @$remote_cap;
          my $ap_flag    = grep {/wlanAccessPoint/} @$remote_cap;

          if ($phone_flag or $remote_type =~ m/(mitel.5\d{3})/i) {
              $remote_type = 'IP Phone: '. $remote_type
                if $remote_type !~ /ip phone/i;
          }
          elsif ($ap_flag) {
              $remote_type = 'AP: '. $remote_type;
          }

          $portrow->update({remote_type => $remote_type});
      }

      if ($portrow->manual_topo) {
          info sprintf ' [%s] neigh - %s has manually defined topology',
            $device->ip, $port;
          next;
      }

      next unless $remote_ip;

      # a bunch of heuristics to search known devices if we don't have a
      # useable remote IP...

      if ($remote_ip eq '0.0.0.0' or
          $remote_ipad->within(NetAddr::IP::Lite->new('127.0.0.0/8'))) {

          if ($remote_id) {
              my $devices = schema('netdisco')->resultset('Device');
              my $neigh = $devices->single({name => $remote_id});
              info sprintf
                ' [%s] neigh - bad address %s on port %s, searching for %s instead',
                $device->ip, $remote_ip, $port, $remote_id;

              if (!defined $neigh) {
                  my $mac = Net::MAC->new(mac => $remote_id, 'die' => 0, verbose => 0);
                  if (not $mac->get_error) {
                      $neigh = $devices->single({mac => $mac->as_IEEE()});
                  }
              }

              # some HP switches send 127.0.0.1 as remote_ip if no ip address
              # on default vlan for HP switches remote_ip looks like
              # "myswitchname(012345-012345)"
              if (!defined $neigh) {
                  (my $tmpid = $remote_id) =~ s/.([0-9a-f]{6})-([0-9a-f]{6})./$1$2/;
                  my $mac = Net::MAC->new(mac => $tmpid, 'die' => 0, verbose => 0);

                  if (not $mac->get_error) {
                      info sprintf
                        '[%s] neigh - found neighbor %s by MAC %s',
                        $device->ip, $remote_id, $mac->as_IEEE();
                      $neigh = $devices->single({mac => $mac->as_IEEE()});
                  }
              }

              if (!defined $neigh) {
                  (my $shortid = $remote_id) =~ s/\..*//;
                  $neigh = $devices->single({name => { -ilike => "${shortid}%" }});
              }

              if ($neigh) {
                  $remote_ip = $neigh->ip;
                  info sprintf ' [%s] neigh - found %s with IP %s',
                    $device->ip, $remote_id, $remote_ip;
              }
              else {
                  info sprintf ' [%s] neigh - could not find %s, skipping',
                    $device->ip, $remote_id;
                  next;
              }
          }
          else {
              info sprintf ' [%s] neigh - skipping unuseable address %s on port %s',
                $device->ip, $remote_ip, $port;
              next;
          }
      }

      # hack for devices seeing multiple neighbors on the port
      if (ref [] eq ref $remote_ip) {
          debug sprintf
            ' [%s] neigh - port %s has multiple neighbors, setting remote as self',
            $device->ip, $port;

          if (wantarray) {
              foreach my $n (@$remote_ip) {
                  debug sprintf
                    ' [%s] neigh - adding neighbor %s, type [%s], on %s to discovery queue',
                    $device->ip, $n, ($remote_type || ''), $port;
                  push @to_discover, [$n, $remote_type];
              }
          }

          # set self as remote IP to suppress any further work
          $remote_ip = $device->ip;
          $remote_port = $port;
      }
      else {
          # what we came here to do.... discover the neighbor
          if (wantarray) {
              debug sprintf
                ' [%s] neigh - adding neighbor %s, type [%s], on %s to discovery queue',
                $device->ip, $remote_ip, ($remote_type || ''), $port;
              push @to_discover, [$remote_ip, $remote_type];
          }

          $remote_port = $c_port->{$entry};

          if (defined $remote_port) {
              # clean weird characters
              $remote_port =~ s/[^\d\/\.,()\w:-]+//gi;
          }
          else {
              info sprintf ' [%s] neigh - no remote port found for port %s at %s',
                $device->ip, $port, $remote_ip;
          }
      }

      $portrow->update({
          remote_ip   => $remote_ip,
          remote_port => $remote_port,
          remote_type => $remote_type,
          remote_id   => $remote_id,
          is_uplink   => \"true",
          manual_topo => \"false",
      });

      if (defined $portrow->slave_of and
          my $master = schema('netdisco')->resultset('DevicePort')
              ->single({ip => $device->ip, port => $portrow->slave_of})) {

          if (not ($portrow->is_master or defined $master->slave_of)) {
              # TODO needs refactoring - this is quite expensive
              my $peer = schema('netdisco')->resultset('DevicePort')->find({
                  ip   => $portrow->neighbor->ip,
                  port => $portrow->remote_port,
              }) if $portrow->neighbor;

              $master->update({
                  remote_ip => ($peer ? $peer->ip : $remote_ip),
                  remote_port => ($peer ? $peer->slave_of : undef ),
                  is_uplink => \"true",
                  manual_topo => \"false",
              });
          }
      }
  }

  return @to_discover;
}

# take data from the topology table and update remote_ip and remote_port
# in the devices table. only use root_ips and skip any bad topo entries.
sub _set_manual_topology {
  my ($device, $snmp) = @_;

  schema('netdisco')->txn_do(sub {
    # clear manual topology flags
    schema('netdisco')->resultset('DevicePort')
      ->search({ip => $device->ip})->update({manual_topo => \'false'});

    my $topo_links = schema('netdisco')->resultset('Topology')
      ->search({-or => [dev1 => $device->ip, dev2 => $device->ip]});
    debug sprintf ' [%s] neigh - setting manual topology links', $device->ip;

    while (my $link = $topo_links->next) {
        # could fail for broken topo, but we ignore to try the rest
        try {
            schema('netdisco')->txn_do(sub {
              # only work on root_ips
              my $left  = get_device($link->dev1);
              my $right = get_device($link->dev2);

              # skip bad entries
              return unless ($left->in_storage and $right->in_storage);

              $left->ports
                ->single({port => $link->port1})
                ->update({
                  remote_ip => $right->ip,
                  remote_port => $link->port2,
                  remote_type => undef,
                  remote_id   => undef,
                  is_uplink   => \"true",
                  manual_topo => \"true",
                });

              $right->ports
                ->single({port => $link->port2})
                ->update({
                  remote_ip => $left->ip,
                  remote_port => $link->port1,
                  remote_type => undef,
                  remote_id   => undef,
                  is_uplink   => \"true",
                  manual_topo => \"true",
                });
            });
        };
    }
  });
}

=head2 discover_new_neighbors( $device, $snmp )

Given a Device database object, and a working SNMP connection, discover and
store the device's port neighbors information.

Entries in the Topology database table will override any discovered device
port relationships.

The Device database object can be a fresh L<DBIx::Class::Row> object which is
not yet stored to the database.

Any discovered neighbor unknown to Netdisco will have a C<discover> job
immediately queued (subject to the filtering by the C<discover_*> settings).

=cut

sub discover_new_neighbors {
  my @to_discover = store_neighbors(@_);

  # only enqueue if device is not already discovered,
  # discover_* config permits the discovery
  foreach my $neighbor (@to_discover) {
      my ($ip, $remote_type) = @$neighbor;

      my $device = get_device($ip);
      next if $device->in_storage;

      if (not is_discoverable($device, $remote_type)) {
          debug sprintf
            ' queue - %s, type [%s] excluded by discover_* config',
            $ip, ($remote_type || '');
          next;
      }

      # Don't queue if job already exists
      if (List::MoreUtils::none {$_ eq $ip} jq_queued('discover')) {
          jq_insert({
              device => $ip,
              action => 'discover',
          });
      }
  }
}

1;
