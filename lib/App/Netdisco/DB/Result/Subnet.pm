use utf8;
package App::Netdisco::DB::Result::Subnet;


use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("subnets");
__PACKAGE__->add_columns(
  "net",
  { data_type => "cidr", is_nullable => 0 },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
  "last_discover",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
);
__PACKAGE__->set_primary_key("net");

1;
