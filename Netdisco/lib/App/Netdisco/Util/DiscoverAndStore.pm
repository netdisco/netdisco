package App::Netdisco::Util::DiscoverAndStore;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::DNS 'hostname_from_ip';
use NetAddr::IP::Lite ':lower';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  store_device store_interfaces store_wireless
  store_vlans store_power
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::DiscoverAndStore

=head1 DESCRIPTION

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

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

  # build device interfaces suitable for DBIC
  my @interfaces;
  foreach my $entry (keys %$ip_index) {
      my $ip = NetAddr::IP::Lite->new($entry);
      my $addr = $ip->addr;

      next if $addr eq '0.0.0.0';
      next if $ip->within(NetAddr::IP::Lite->new('127.0.0.0/8'));
      next if setting('ignore_private_nets') and $ip->is_rfc1918;

      my $iid = $ip_index->{$addr};
      my $port = $interfaces->{$iid};
      my $subnet = $ip_netmask->{$addr}
        ? NetAddr::IP::Lite->new($addr, $ip_netmask->{$addr})->network->cidr
        : undef;

      push @interfaces, {
          alias => $addr,
          port => $port,
          subnet => $subnet,
          dns => hostname_from_ip($addr),
      };
  }

  # VTP Management Domain -- assume only one.
  my $vtpdomains = $snmp->vtp_d_name;
  my $vtpdomain;
  if (defined $vtpdomains and scalar values %$vtpdomains) {
      $device->vtp_domain( (values %$vtpdomains)[-1] );
  }

  my $hostname = hostname_from_ip($device->ip);
  $device->dns($hostname) if length $hostname;

  my @properties = qw/
    snmp_ver snmp_comm
    description uptime contact name location
    layers ports mac serial model
    ps1_type ps2_type ps1_status ps2_status
    fan slots
    vendor os os_ver
  /;

  foreach my $property (@properties) {
      $device->$property( $snmp->$property );
  }

  $device->snmp_class( $snmp->class );
  $device->last_discover(\'now()');

  schema('netdisco')->txn_do(sub {
    $device->device_ips->delete;
    $device->update_or_insert;
    $device->device_ips->populate(\@interfaces);
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
  my $i_pvid         = $snmp->i_pvid;
  my $i_lastchange   = $snmp->i_lastchange;

  # clear the cached uptime...
  # I think I just threw up a little in my mouth.
  delete $snmp->{_uptime};
  my $dev_uptime = $snmp->uptime;

  if (scalar grep {$_ > $dev_uptime} values %$i_lastchange) {
      $device->uptime( $dev_uptime + 2**32 );
  }

  # build device interfaces suitable for DBIC
  my @interfaces;
  foreach my $entry (keys %$interfaces) {
      my $port = $interfaces->{$entry};

      if (not length $port) {
          # TODO log message
          next;
      }

      if (scalar grep {$port =~ m/$_/} @{setting('ignore_interfaces') || []}) {
          # TODO log message
          next;
      }

      my $lc = $i_lastchange->{$entry};
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
                  $lc += 2**32;
                  # TODO log message
              }
          }
      }

      push @interfaces, {
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
          vlan         => $i_vlan->{$entry},
          pvid         => $i_pvid->{$entry},
          lastchange   => $lc,
      };
  }

  schema('netdisco')->txn_do(sub {
    $device->ports->delete;
    $device->update_or_insert;
    $device->ports->populate(\@interfaces);
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
  my $power      = $snmp->i_dot11_cur_tx_pwr_mw;

  # build device ssid list suitable for DBIC
  my @ssids;
  foreach my $entry (keys %$ssidlist) {
      $entry =~ s/\.\d+$//;
      my $port = $interfaces->{$entry};

      if (not length $port) {
          # TODO log message
          next;
      }

      push @ssids, {
          port      => $port,
          ssid      => $ssidlist->{$entry},
          broadcast => $ssidbcast->{$entry},
          bssid     => $ssidmac->{$entry},
      };
  }

  # build device channel list suitable for DBIC
  my @channels;
  foreach my $entry (keys %$channel) {
      $entry =~ s/\.\d+$//;
      my $port = $interfaces->{$entry};

      if (not length $port) {
          # TODO log message
          next;
      }

      push @channels, {
          port    => $port,
          channel => $channel->{$entry},
          power   => $power->{$entry},
      };
  }

  # FIXME not sure what relations need adding for wireless ports
  # 
  #schema('netdisco')->txn_do(sub {
  #  $device->ports->delete;
  #  $device->update_or_insert;
  #  $device->ports->populate(\@interfaces);
  #});
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
  my %portvlans;
  foreach my $entry (keys %$i_vlan_membership) {
      my $port = $interfaces->{$entry};
      next unless defined $port;

      my $type = $i_vlan_type->{$entry};
      $portvlans{$port} = [];

      foreach my $vlan (@{ $i_vlan_membership->{$entry} }) {
          my $native = ((defined $i_vlan->{$entry}) and ($vlan eq $i_vlan->{$entry})) ? "t" : "f";
          push @{$portvlans{$port}}, {
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
    $device->vlans->delete;
    $device->vlans->populate(\@devicevlans);

    foreach my $port (keys %portvlans) {
        my $port = $device->ports->find({port => $port});
        $port->vlans->delete;
        $port->vlans->populate($portvlans{$port});
    }
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
      # TODO log
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
  my %portpower;
  foreach my $entry (keys %$p_ifindex) {
      my $port = $interfaces->{ $p_ifindex->{$entry} };
      next unless $port;

      my ($module) = split m/\./, $entry;
      $portpower{$port} = [];

      push @{$portpower{$port}}, {
          module => $module,
          admin  => $p_admin->{$entry},
          status => $p_pstatus->{$entry},
          class  => $p_class->{$entry},
          power  => $p_power->{$entry},

      };
  }

  schema('netdisco')->txn_do(sub {
    $device->power_modules->delete;
    $device->power_modules->populate(\@devicepower);

    foreach my $port (keys %portpower) {
        my $port = $device->ports->find({port => $port});
        $port->power->delete if $port->power;
        $port->create_related('power', $portpower{$port});
    }
  });
}

1;
