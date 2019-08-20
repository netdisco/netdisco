use utf8;
package App::Netdisco::DB::Result::DevicePortPower;


use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("device_port_power");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "port",
  { data_type => "text", is_nullable => 0 },
  "module",
  { data_type => "integer", is_nullable => 1 },
  "admin",
  { data_type => "text", is_nullable => 1 },
  "status",
  { data_type => "text", is_nullable => 1 },
  "class",
  { data_type => "text", is_nullable => 1 },
  "power",
  { data_type => "integer", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("port", "ip");



=head1 RELATIONSHIPS

=head2 port

Returns the entry from the C<port> table for which this Power entry applies.

=cut

__PACKAGE__->belongs_to( port => 'App::Netdisco::DB::Result::DevicePort', {
  'foreign.ip' => 'self.ip', 'foreign.port' => 'self.port',
});

=head2 device_module

Returns the entry from the C<device_power> table for which this Power entry
applies.

=cut

__PACKAGE__->belongs_to( device_module => 'App::Netdisco::DB::Result::DevicePower', {
  'foreign.ip' => 'self.ip', 'foreign.module' => 'self.module',
});

1;
