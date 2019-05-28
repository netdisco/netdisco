use utf8;
package App::Netdisco::DB::Result::DeviceModule;


use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("device_module");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "index",
  { data_type => "integer", is_nullable => 0 },
  "description",
  { data_type => "text", is_nullable => 1 },
  "type",
  { data_type => "text", is_nullable => 1 },
  "parent",
  { data_type => "integer", is_nullable => 1 },
  "name",
  { data_type => "text", is_nullable => 1 },
  "class",
  { data_type => "text", is_nullable => 1 },
  "pos",
  { data_type => "integer", is_nullable => 1 },
  "hw_ver",
  { data_type => "text", is_nullable => 1 },
  "fw_ver",
  { data_type => "text", is_nullable => 1 },
  "sw_ver",
  { data_type => "text", is_nullable => 1 },
  "serial",
  { data_type => "text", is_nullable => 1 },
  "model",
  { data_type => "text", is_nullable => 1 },
  "fru",
  { data_type => "boolean", is_nullable => 1 },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
  "last_discover",
  { data_type => "timestamp", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("ip", "index");



=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table on which this VLAN entry was discovered.

=cut

__PACKAGE__->belongs_to( device => 'App::Netdisco::DB::Result::Device', 'ip' );

1;
