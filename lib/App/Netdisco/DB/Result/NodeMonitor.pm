use utf8;
package App::Netdisco::DB::Result::NodeMonitor;


use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("node_monitor");
__PACKAGE__->add_columns(
  "mac",
  { data_type => "macaddr", is_nullable => 0 },
  "matchoui",
  { data_type => "boolean", is_nullable => 1 },
  "active",
  { data_type => "boolean", is_nullable => 1 },
  "why",
  { data_type => "text", is_nullable => 1 },
  "cc",
  { data_type => "text", is_nullable => 1 },
  "date",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
);
__PACKAGE__->set_primary_key("mac");


1;
