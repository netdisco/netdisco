use utf8;
package App::Netdisco::DB::Result::Product;

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("product");
__PACKAGE__->add_columns(
  "oid",
  { data_type => "text", is_nullable => 0 },
  "mib",
  { data_type => "text", is_nullable => 0 },
  "leaf",
  { data_type => "text", is_nullable => 0 },
  "descr",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("oid");

1;
