package App::Netdisco::Util::DiscoverAndStore;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::DNS 'hostname_from_ip';
use NetAddr::IP::Lite ':lower';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  store_device store_interfaces
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
  $device->last_discover(scalar localtime);

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

1;
