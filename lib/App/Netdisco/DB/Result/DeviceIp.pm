use utf8;
package App::Netdisco::DB::Result::DeviceIp;


use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
use Sub::Install;

__PACKAGE__->table("device_ip");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "alias",
  { data_type => "inet", is_nullable => 0 },
  "subnet",
  { data_type => "cidr", is_nullable => 1 },
  "port",
  { data_type => "text", is_nullable => 1 },
  "dns",
  { data_type => "text", is_nullable => 1 },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
);
__PACKAGE__->set_primary_key("ip", "alias");



=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table to which this IP alias relates.

=cut

__PACKAGE__->belongs_to( device => 'App::Netdisco::DB::Result::Device', 'ip' );

=head2 device_port

Returns the Port on which this IP address is configured (typically a loopback,
routed port or virtual interface).

=cut

__PACKAGE__->belongs_to( device_port => 'App::Netdisco::DB::Result::DevicePort',
  { 'foreign.port' => 'self.port', 'foreign.ip' => 'self.ip' } );

=head2 device_port fields

Useful C<device_port> fields are mapped to accessors on this object.

=cut

foreach my $field (qw/
  descr
  up
  up_admin
  type
  duplex
  duplex_admin
  speed
  speed_admin
  name
  mac
  mtu
  stp
  remote_ip
  remote_port
  remote_type
  remote_id
  vlan
  pvid
  manual_topo
  is_uplink
  slave_of
  is_master
  has_subinterfaces
    /) {

  Sub::Install::install_sub({
    code => sub { return eval { (shift)->device_port->$field } },
    as   => $field,
  });
}

=head2 device_port_properties fields

Useful C<device_port_properties> fields are mapped to accessors on this object.

=cut

foreach my $field (qw/
  remote_is_wap
  remote_is_phone
  remote_vendor
  remote_model
  remote_os_ver
  remote_is_discoverable
  remote_dns
    /) {

  Sub::Install::install_sub({
    code => sub { return eval { (shift)->device_port->properties->$field } },
    as   => $field,
  });
}

1;
