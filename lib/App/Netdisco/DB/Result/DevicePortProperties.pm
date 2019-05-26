use utf8;
package App::Netdisco::DB::Result::DevicePortProperties;

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("device_port_properties");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "port",
  { data_type => "text", is_nullable => 0 },
  "error_disable_cause",
  { data_type => "text", is_nullable => 1 },
  "remote_is_wap",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
  "remote_is_phone",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
  "remote_vendor",
  { data_type => "text", is_nullable => 1 },
  "remote_model",
  { data_type => "text", is_nullable => 1 },
  "remote_os_ver",
  { data_type => "text", is_nullable => 1 },
  "remote_serial",
  { data_type => "text", is_nullable => 1 },
  "raw_speed",
  { data_type => "bigint", default_value => 0, is_nullable => 1 },
  "faststart",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
  "ifindex",
  { data_type => "bigint", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("port", "ip");


=head1 RELATIONSHIPS

=head2 port

Returns the entry from the C<port> table for which this Power entry applies.

=cut

__PACKAGE__->belongs_to( port => 'App::Netdisco::DB::Result::DevicePort', {
  'foreign.ip' => 'self.ip', 'foreign.port' => 'self.port',
});

1;
