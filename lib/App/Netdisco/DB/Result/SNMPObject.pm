use utf8;
package App::Netdisco::DB::Result::SNMPObject;

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("snmp_object");
__PACKAGE__->add_columns(
  "oid",
  { data_type => "text", is_nullable => 0 },
  "oid_parts",
  { data_type => "integer[]", is_nullable => 0 },
  "mib",
  { data_type => "text", is_nullable => 0 },
  "leaf",
  { data_type => "text", is_nullable => 0 },
  "type",
  { data_type => "text", is_nullable => 1 },
  "access",
  { data_type => "text", is_nullable => 1 },
  "index",
  { data_type => "text[]", is_nullable => 1, default_value => \"'{}'::text[]" },
  "num_children",
  { data_type => "integer", is_nullable => 0, default_value => \'0' },
  "status",
  { data_type => "text", is_nullable => 1 },
  "enum",
  { data_type => "text[]", is_nullable => 1, default_value => \"'{}'::text[]" },
  "descr",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("oid");

__PACKAGE__->might_have( device_browser => 'App::Netdisco::DB::Result::DeviceBrowser', 'oid' );

1;
