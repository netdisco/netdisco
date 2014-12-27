use utf8;
package App::Netdisco::DB::Result::DevicePortStp;

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("device_port_stp");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "port",
  { data_type => "text", is_nullable => 0 },
  "instance",
  { data_type => "integer", is_nullable => 0 },
  "port_id",
  { data_type => "integer", is_nullable => 0 },
  "des_bridge_mac",
  { data_type => "macaddr", is_nullable => 1 },
  "des_port_id",
  { data_type => "integer", is_nullable => 1 },
  "status",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("port", "ip", "instance");


=head1 RELATIONSHIPS

=head2 port

Returns the entry from the C<port> table for which this Power entry applies.

=cut

__PACKAGE__->belongs_to( port => 'App::Netdisco::DB::Result::DevicePort', {
  'foreign.ip' => 'self.ip', 'foreign.port' => 'self.port',
});

=head2 stp_instance

Returns the entry from the C<device_stp> table for which this STP entry
applies.

=cut

__PACKAGE__->belongs_to( device_stp => 'App::Netdisco::DB::Result::DeviceStp', {
  'foreign.ip' => 'self.ip', 'foreign.instance' => 'self.instance',
});

1;
