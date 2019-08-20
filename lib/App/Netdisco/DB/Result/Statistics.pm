use utf8;
package App::Netdisco::DB::Result::Statistics;

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("statistics");
__PACKAGE__->add_columns(
  "day",
  { data_type => "date", default_value => \"CURRENT_DATE", is_nullable => 0 },
  "device_count",
  { data_type => "integer", is_nullable => 0 },
  "device_ip_count",
  { data_type => "integer", is_nullable => 0 },
  "device_link_count",
  { data_type => "integer", is_nullable => 0 },
  "device_port_count",
  { data_type => "integer", is_nullable => 0 },
  "device_port_up_count",
  { data_type => "integer", is_nullable => 0 },
  "ip_table_count",
  { data_type => "integer", is_nullable => 0 },
  "ip_active_count",
  { data_type => "integer", is_nullable => 0 },
  "node_table_count",
  { data_type => "integer", is_nullable => 0 },
  "node_active_count",
  { data_type => "integer", is_nullable => 0 },
  "netdisco_ver",
  { data_type => "text", is_nullable => 1 },
  "snmpinfo_ver",
  { data_type => "text", is_nullable => 1 },
  "schema_ver",
  { data_type => "text", is_nullable => 1 },
  "perl_ver",
  { data_type => "text", is_nullable => 1 },
  "pg_ver",
  { data_type => "text", is_nullable => 1 },
);

__PACKAGE__->set_primary_key("day");

1;
