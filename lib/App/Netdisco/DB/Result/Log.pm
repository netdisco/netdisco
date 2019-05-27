use utf8;
package App::Netdisco::DB::Result::Log;


use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("log");
__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "integer",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "log_id_seq",
  },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
  "class",
  { data_type => "text", is_nullable => 1 },
  "entry",
  { data_type => "text", is_nullable => 1 },
  "logfile",
  { data_type => "text", is_nullable => 1 },
);




# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
