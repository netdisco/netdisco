package App::Netdisco::Util::DiscoverAndStore;

use Dancer qw/:syntax :script/;

use App::Netdisco::Util::DNS 'hostname_from_ip';
use NetAddr::IP::Lite ':lower';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  store_device
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

1;
