use utf8;
package App::Netdisco::DB::Result::Process;


use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
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
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
);


1;
