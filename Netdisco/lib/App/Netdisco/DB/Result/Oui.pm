use utf8;
package App::Netdisco::DB::Result::Oui;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("oui");
__PACKAGE__->add_columns(
  "oui",
  { data_type => "varchar", is_nullable => 0, size => 8 },
  "company",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("oui");


# Created by DBIx::Class::Schema::Loader v0.07015 @ 2012-01-07 14:20:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:s51mj6SvstPd4GdNEy9SoA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
