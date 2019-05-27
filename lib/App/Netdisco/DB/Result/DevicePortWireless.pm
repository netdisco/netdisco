use utf8;
package App::Netdisco::DB::Result::DevicePortWireless;


use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("device_port_wireless");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "port",
  { data_type => "text", is_nullable => 0 },
  "channel",
  { data_type => "integer", is_nullable => 1 },
  "power",
  { data_type => "integer", is_nullable => 1 },
);

__PACKAGE__->set_primary_key("port", "ip");


=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table which hosts this wireless port.

=cut

__PACKAGE__->belongs_to( device => 'App::Netdisco::DB::Result::Device', 'ip' );

=head2 port

Returns the entry from the C<port> table which corresponds to this wireless
interface.

=cut

__PACKAGE__->belongs_to( port => 'App::Netdisco::DB::Result::DevicePort', {
    'foreign.ip' => 'self.ip', 'foreign.port' => 'self.port',
});

=head2 nodes

Returns the set of Nodes whose MAC addresses are associated with this Device
Port Wireless.

=cut

__PACKAGE__->has_many( nodes => 'App::Netdisco::DB::Result::Node',
  {
    'foreign.switch' => 'self.ip',
    'foreign.port' => 'self.port',
  },
  { join_type => 'LEFT',
    cascade_copy => 0, cascade_update => 0, cascade_delete => 0 },
);

# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
