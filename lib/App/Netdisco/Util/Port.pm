package App::Netdisco::Util::Port;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::Device 'get_device';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  vlan_reconfig_check port_reconfig_check
  get_port get_iid get_powerid
  is_vlan_interface port_has_phone
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::Port

=head1 DESCRIPTION

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 vlan_reconfig_check( $port )

=over 4

=item *

Sanity check that C<$port> is not a vlan subinterface.

=item *

Permission check that C<vlanctl> is true in Netdisco config.

=back

Will return nothing if these checks pass OK.

=cut

sub vlan_reconfig_check {
  my $port = shift;
  my $ip = $port->ip;
  my $name = $port->port;

  my $is_vlan = is_vlan_interface($port);

  # vlan (routed) interface check
  return "forbidden: [$name] is a vlan interface on [$ip]"
    if $is_vlan;

  return "forbidden: not permitted to change native vlan"
    if not setting('vlanctl');

  return;
}

=head2 port_reconfig_check( $port )

=over 4

=item *

Permission check that C<portctl_nameonly> is false in Netdisco config.

=item *

Permission check that C<portctl_uplinks> is true in Netdisco config, if
C<$port> is an uplink.

=item *

Permission check that C<portctl_nophones> is not true in Netdisco config, if
C<$port> has a phone connected.

=item *

Permission check that C<portctl_vlans> is true if C<$port> is a vlan
subinterface.

=back

Will return nothing if these checks pass OK.

=cut

sub port_reconfig_check {
  my $port = shift;
  my $ip = $port->ip;
  my $name = $port->port;

  my $has_phone = port_has_phone($port);
  my $is_vlan   = is_vlan_interface($port);

  # only permitted to change interface name
  return "forbidden: not permitted to change port configuration"
    if setting('portctl_nameonly');

  # uplink check
  return "forbidden: port [$name] on [$ip] is an uplink"
    if ($port->is_uplink or $port->remote_type)
        and not $has_phone and not setting('portctl_uplinks');

  # phone check
  return "forbidden: port [$name] on [$ip] is a phone"
    if $has_phone and setting('portctl_nophones');

  # vlan (routed) interface check
  return "forbidden: [$name] is a vlan interface on [$ip]"
    if $is_vlan and not setting('portctl_vlans');

  return;
}

=head2 get_port( $device, $portname )

Given a device IP address and a port name, returns a L<DBIx::Class::Row>
object for the Port on the Device in the Netdisco database.

The device IP can also be passed as a Device C<DBIx::Class> object.

Returns C<undef> if the device or port are not known to Netdisco.

=cut

sub get_port {
  my ($device, $portname) = @_;

  # accept either ip or dbic object
  $device = get_device($device);

  my $port = schema('netdisco')->resultset('DevicePort')
    ->find({ip => $device->ip, port => $portname});

  return $port;
}

=head2 get_iid( $info, $port )

Given an L<SNMP::Info> instance for a device, and the name of a port, returns
the current interface table index for that port. This can be used in further
SNMP requests on attributes of the port.

Returns C<undef> if there is no such port name on the device.

=cut

sub get_iid {
  my ($info, $port) = @_;

  # accept either port name or dbic object
  $port = $port->port if ref $port;

  my $interfaces = $info->interfaces;
  my %rev_if     = reverse %$interfaces;
  my $iid        = $rev_if{$port};

  return $iid;
}

=head2 get_powerid( $info, $port )

Given an L<SNMP::Info> instance for a device, and the name of a port, returns
the current PoE table index for the port. This can be used in further SNMP
requests on PoE attributes of the port.

Returns C<undef> if there is no such port name on the device.

=cut

sub get_powerid {
  my ($info, $port) = @_;

  # accept either port name or dbic object
  $port = $port->port if ref $port;

  my $iid = get_iid($info, $port)
    or return undef;

  my $p_interfaces = $info->peth_port_ifindex;
  my %rev_p_if     = reverse %$p_interfaces;
  my $powerid      = $rev_p_if{$iid};

  return $powerid;
}

=head2 is_vlan_interface( $port )

Returns true if the C<$port> L<DBIx::Class> object represents a vlan
subinterface.

This uses simple checks on the port I<type> and I<descr>, and therefore might
sometimes returns a false-negative result.

=cut

sub is_vlan_interface {
  my $port = shift;

  my $is_vlan  = (($port->type and
    $port->type =~ /^(53|propVirtual|l2vlan|l3ipvlan|135|136|137)$/i)
    or ($port->port and $port->port =~ /vlan/i)
    or ($port->descr and $port->descr =~ /vlan/i)) ? 1 : 0;

  return $is_vlan;
}

=head2 port_has_phone( $port )

Returns true if the C<$port> L<DBIx::Class> object has a phone connected.

=cut

sub port_has_phone {
  my $properties = (shift)->properties;
  return ($properties ? $properties->remote_is_phone : undef);
}

1;
