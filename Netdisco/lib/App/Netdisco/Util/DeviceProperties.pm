package App::Netdisco::Util::DeviceProperties;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use NetAddr::IP::Lite ':lower';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  is_discoverable
  is_vlan_interface port_has_phone
/;
our %EXPORT_TAGS = (
  all => [qw/
    is_discoverable
    is_vlan_interface port_has_phone
  /],
);

=head1 App::Netdisco::Util::DeviceProperties;

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head2 is_discoverable( $ip )

Given an IP address, returns C<true> if Netdisco on this host is permitted to
discover its configuration by the local configuration.

The configuration items C<discover_no> and C<discover_only> are checked
against the given IP.

Returns false if the host is not permitted to discover the target device.

=cut

sub is_discoverable {
  my $q = shift;

  my $device = schema('netdisco')->resultset('Device')
    ->search_for_device($q) or return 0;
  my $addr = NetAddr::IP::Lite->new($device->ip);

  my $discover_no   = setting('discover_no') || [];
  my $discover_only = setting('discover_only') || [];

  if (scalar @$discover_no) {
      foreach my $item (@$discover_no) {
          my $ip = NetAddr::IP::Lite->new($item) or return 0;
          return 0 if $ip->contains($addr);
      }
  }

  if (scalar @$discover_only) {
      my $okay = 0;
      foreach my $item (@$discover_only) {
          my $ip = NetAddr::IP::Lite->new($item) or return 0;
          ++$okay if $ip->contains($addr);
      }
      return 0 if not $okay;
  }

  return 1;
}

=head2 is_vlan_interface( $port )

=cut

sub is_vlan_interface {
  my $port = shift;

  my $is_vlan  = (($port->type and
    $port->type =~ /^(53|propVirtual|l2vlan|l3ipvlan|135|136|137)$/i)
    or ($port->port and $port->port =~ /vlan/i)
    or ($port->name and $port->name =~ /vlan/i)) ? 1 : 0;

  return $is_vlan;
}

=head2 port_has_phone( $port )

=cut

sub port_has_phone {
  my $port = shift;

  my $has_phone = ($port->remote_type
    and $port->remote_type =~ /ip.phone/i) ? 1 : 0;

  return $has_phone;
}

1;
