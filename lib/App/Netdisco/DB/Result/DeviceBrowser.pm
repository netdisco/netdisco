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
  "value",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("ip", "oid");

1;
