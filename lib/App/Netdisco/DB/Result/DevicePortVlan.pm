use utf8;
package App::Netdisco::DB::Result::DevicePortVlan;


use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("device_port_vlan");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "port",
  { data_type => "text", is_nullable => 0 },
  "vlan",
  { data_type => "integer", is_nullable => 0 },
  "native",
  { data_type => "boolean", default_value => \"false", is_nullable => 0 },
  "egress_tag",
  { data_type => "boolean", default_value => \"true",  is_nullable => 0 },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
  "last_discover",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
  "vlantype",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("ip", "port", "vlan", "native");



=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table which hosts the Port on which this
VLAN is configured.

=cut

__PACKAGE__->belongs_to( device => 'App::Netdisco::DB::Result::Device', 'ip' );

=head2 port

Returns the entry from the C<port> table on which this VLAN is configured.

=cut

__PACKAGE__->belongs_to( port => 'App::Netdisco::DB::Result::DevicePort', {
    'foreign.ip' => 'self.ip', 'foreign.port' => 'self.port',
});

=head2 vlan

Returns the entry from the C<device_vlan> table describing this VLAN in
detail, typically in order that the C<name> can be retrieved.

=cut

__PACKAGE__->belongs_to( vlan => 'App::Netdisco::DB::Result::DeviceVlan', {
    'foreign.ip' => 'self.ip', 'foreign.vlan' => 'self.vlan',
});

1;
