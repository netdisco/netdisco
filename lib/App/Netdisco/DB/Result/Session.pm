use utf8;
package App::Netdisco::DB::Result::Session;


use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("sessions");
__PACKAGE__->add_columns(
  "id",
  { data_type => "char", is_nullable => 0, size => 32 },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
  "a_session",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");

1;
