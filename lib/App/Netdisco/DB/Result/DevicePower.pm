use utf8;
package App::Netdisco::DB::Result::DevicePower;


use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("device_power");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "module",
  { data_type => "integer", is_nullable => 0 },
  "power",
  { data_type => "integer", is_nullable => 1 },
  "status",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("ip", "module");



=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table on which this power module was discovered.

=cut

__PACKAGE__->belongs_to( device => 'App::Netdisco::DB::Result::Device', 'ip' );

=head2 ports

Returns the set of PoE ports associated with a power module.

=cut

__PACKAGE__->has_many( ports => 'App::Netdisco::DB::Result::DevicePortPower', {
  'foreign.ip' => 'self.ip', 'foreign.module' => 'self.module',
} );

1;
