package Netdisco::Util::Permissions;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use Netdisco::Util::DeviceProperties ':all';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  vlan_reconfig_check port_reconfig_check
/;
our %EXPORT_TAGS = (
  all => [qw/
    vlan_reconfig_check port_reconfig_check
  /],
);

=head1 Netdisco::Util::Permissions

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head2 vlan_reconfig_check( $port )

=cut

sub vlan_reconfig_check {
  my $port = shift;
  my $ip = $port->ip;
  my $name = $port->port;
  my $nd_config = var('nd_config')->{_};

  my $is_vlan = is_vlan_interface($port);

  # vlan (routed) interface check
  return "forbidden: [$name] is a vlan interface on [$ip]"
    if $is_vlan;

  return "forbidden: not permitted to change native vlan"
    if not $nd_config->{vlanctl};

  return;
}

=head2 port_reconfig_check( $port )

=cut

sub port_reconfig_check {
  my $port = shift;
  my $ip = $port->ip;
  my $name = $port->port;
  my $nd_config = var('nd_config')->{_};

  my $has_phone = has_phone($port);
  my $is_vlan   = is_vlan_interface($port);

  # uplink check
  return "forbidden: port [$name] on [$ip] is an uplink"
    if $port->remote_type and not $has_phone and not $nd_config->{allow_uplinks};

  # phone check
  return "forbidden: port [$name] on [$ip] is a phone"
    if $has_phone and $nd_config->{portctl_nophones};

  # vlan (routed) interface check
  return "forbidden: [$name] is a vlan interface on [$ip]"
    if $is_vlan and not $nd_config->{portctl_vlans};

  return;
}

1;
