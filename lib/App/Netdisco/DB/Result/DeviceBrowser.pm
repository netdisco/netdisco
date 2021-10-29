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
  "value",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("ip", "oid");

=head1 RELATIONSHIPS

=head2 snmp_object

Returns the SNMP Object table entry to which the given row is related.

=cut

__PACKAGE__->belongs_to(
  snmp_object => 'App::Netdisco::DB::Result::SNMPObject',
  'oid', { join_type => 'RIGHT' }
);

1;
