use utf8;
package App::Netdisco::DB::Result::Community;

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("community");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "snmp_comm_rw",
  { data_type => "text", is_nullable => 1 },
  "snmp_auth_tag",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("ip");

1;
