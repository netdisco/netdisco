use utf8;
package App::Netdisco::DB::Result::DeviceVlan;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("device_vlan");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "vlan",
  { data_type => "integer", is_nullable => 0 },
  "description",
  { data_type => "text", is_nullable => 1 },
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
);
__PACKAGE__->set_primary_key("ip", "vlan");


# Created by DBIx::Class::Schema::Loader v0.07015 @ 2012-01-07 14:20:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:hBJRcdzOic4d3u4pD1m8iA

=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table on which this VLAN entry was discovered.

=cut

__PACKAGE__->belongs_to( device => 'App::Netdisco::DB::Result::Device', 'ip' );

=head2 port_vlans_tagged

Link relationship for C<tagging_ports>, see below.

=cut

__PACKAGE__->has_many( port_vlans_tagged => 'App::Netdisco::DB::Result::Virtual::DevicePortVlanTagged',
    { 'foreign.ip' => 'self.ip', 'foreign.vlan' => 'self.vlan' },
    { cascade_copy => 0, cascade_update => 0, cascade_delete => 0 }
);

=head2 port_vlans_native

Link relationship to support C<native_ports>, see below.

=cut

__PACKAGE__->has_many( port_vlans_native => 'App::Netdisco::DB::Result::Virtual::DevicePortVlanNative',
    { 'foreign.ip' => 'self.ip', 'foreign.vlan' => 'self.vlan' },
    { cascade_copy => 0, cascade_update => 0, cascade_delete => 0 }
);

=head2 tagging_ports

Returns the set of Device Ports on which this VLAN is configured to be tagged.

=cut

__PACKAGE__->many_to_many( tagging_ports => 'port_vlans_tagged', 'port' );

=head2 native_ports

Returns the set of Device Ports on which this VLAN is the native VLAN (that
is, untagged).

=cut

__PACKAGE__->many_to_many( native_ports  => 'port_vlans_native', 'port' );

1;
