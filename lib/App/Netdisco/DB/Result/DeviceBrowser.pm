use utf8;
package App::Netdisco::DB::Result::DeviceBrowser;

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("device_browser");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "oid",
  { data_type => "text", is_nullable => 0 },
  "oid_parts",
  { data_type => "integer[]", is_nullable => 0 },
  "leaf",
  { data_type => "text", is_nullable => 0 },
  "munge",
  { data_type => "text", is_nullable => 1 },
  "value",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("ip", "oid");

=head1 RELATIONSHIPS

=head2 snmp_object

Returns the SNMP Object table entry to which the given row is related. The
idea is that you always get the SNMP Object row data even if the Device
Browser table doesn't have any walked data.

However you probably want to use the C<snmp_object> method in the
C<DeviceBrowser> ResultSet instead, so you can pass the IP address.

=cut

__PACKAGE__->belongs_to(
  snmp_object => 'App::Netdisco::DB::Result::SNMPObject',
  sub {
    my $args = shift;
    return {
        "$args->{self_alias}.oid" => { -ident => "$args->{foreign_alias}.oid" },
        "$args->{self_alias}.ip" => { '=' => \'?' },
    };
  },
  { join_type => 'RIGHT' }
);

1;
