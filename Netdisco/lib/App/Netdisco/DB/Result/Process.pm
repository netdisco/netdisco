use utf8;
package App::Netdisco::DB::Result::Process;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("process");
__PACKAGE__->add_columns(
  "controller",
  { data_type => "integer", is_nullable => 0 },
  "device",
  { data_type => "inet", is_nullable => 0 },
  "action",
  { data_type => "text", is_nullable => 0 },
  "status",
  { data_type => "text", is_nullable => 1 },
  "count",
  { data_type => "integer", is_nullable => 1 },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
);


# Created by DBIx::Class::Schema::Loader v0.07015 @ 2012-01-07 14:20:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:28hTnOo4oNwJabiWWHBgCw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
