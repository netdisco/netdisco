use utf8;
package App::Netdisco::DB::Result::DeviceStp;

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("device_stp");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "instance",
  { data_type => "integer", is_nullable => 0 },
  "mac",
  { data_type => "macaddr", is_nullable => 1 },
  "top_change",
  { data_type => "integer", is_nullable => 1 },
  "top_lastchange",
  { data_type => "bigint", is_nullable => 1 },
  "des_root_mac",
  { data_type => "macaddr", is_nullable => 1 },
  "root_port",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("ip", "instance");


=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table to which this STP instance relates.

=cut

__PACKAGE__->belongs_to( device => 'App::Netdisco::DB::Result::Device', 'ip' );

=head2 stp_ports

Returns the set of STP instances known to be configured on Ports on this
Device.

=cut

__PACKAGE__->has_many(
    ports => 'App::Netdisco::DB::Result::DevicePortStp',
  {
    'foreign.ip' => 'self.ip',
    'foreign.instance' => 'self.instance',
  },
);

1;
