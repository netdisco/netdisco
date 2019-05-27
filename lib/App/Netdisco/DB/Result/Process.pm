use utf8;
package App::Netdisco::DB::Result::Process;


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




# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
