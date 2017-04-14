use utf8;
package App::Netdisco::DB::Result::DeviceIp;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';
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
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
);
__PACKAGE__->set_primary_key("ip", "alias");


# Created by DBIx::Class::Schema::Loader v0.07015 @ 2012-01-07 14:20:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:/ugGtBSGyrJ7s6yqJ9bclQ

=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table to which this IP alias relates.

=cut

__PACKAGE__->belongs_to( device => 'App::Netdisco::DB::Result::Device', 'ip' );

=head2 device_port

Returns the Port on which this IP address is configured (typically a loopback,
routed port or virtual interface).

=cut

__PACKAGE__->add_unique_constraint(['alias']);

__PACKAGE__->belongs_to( device_port => 'App::Netdisco::DB::Result::DevicePort',
  { 'foreign.port' => 'self.port', 'foreign.ip' => 'self.ip' } );

1;
