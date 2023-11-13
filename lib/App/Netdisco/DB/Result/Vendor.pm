use utf8;
package App::Netdisco::DB::Result::Vendor;

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("vendor");

__PACKAGE__->add_columns(
  "company",
  { data_type => "text", is_nullable => 1 },
  "abbrev",
  { data_type => "text", is_nullable => 1 },
  "base",
  { data_type => "text", is_nullable => 0 },
  "bits",
  { data_type => "integer", is_nullable => 1 },
  "first",
  { data_type => "macaddr", is_nullable => 1 },
  "last",
  { data_type => "macaddr", is_nullable => 1 },
  "range",
  { data_type => "int8range", is_nullable => 1 },
  "oui",
  { data_type => "varchar", is_nullable => 1, size => 8 },
);

__PACKAGE__->set_primary_key("base");

1;
