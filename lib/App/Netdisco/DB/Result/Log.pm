use utf8;
package App::Netdisco::DB::Result::Log;


use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
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
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
  "class",
  { data_type => "text", is_nullable => 1 },
  "entry",
  { data_type => "text", is_nullable => 1 },
  "logfile",
  { data_type => "text", is_nullable => 1 },
);

1;
