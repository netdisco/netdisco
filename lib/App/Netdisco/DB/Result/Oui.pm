use utf8;
package App::Netdisco::DB::Result::Oui;


use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("oui");
__PACKAGE__->add_columns(
  "oui",
  { data_type => "varchar", is_nullable => 0, size => 8 },
  "company",
  { data_type => "text", is_nullable => 1 },
  "abbrev",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("oui");

1;
