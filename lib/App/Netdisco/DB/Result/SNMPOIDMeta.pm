use utf8;
package App::Netdisco::DB::Result::SNMPOIDMeta;

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("snmp_oid_meta");
__PACKAGE__->add_columns(
  "oid",
  { data_type => "text", is_nullable => 0 },
  "mib",
  { data_type => "text", is_nullable => 0 },
  "leaf",
  { data_type => "text", is_nullable => 0 },
  "type",
  { data_type => "text", is_nullable => 1 },
  "munge",
  { data_type => "text", is_nullable => 1 },
  "access",
  { data_type => "text", is_nullable => 1 },
  "index",
  { data_type => "text[]", is_nullable => 1, default_value => \"'{}'::text[]" },
);
__PACKAGE__->set_primary_key("oid");

1;
