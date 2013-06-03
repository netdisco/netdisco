use utf8;
package App::Netdisco::DB::Result::NodeWireless;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("node_wireless");
__PACKAGE__->add_columns(
  "mac",
  { data_type => "macaddr", is_nullable => 0 },
  "uptime",
  { data_type => "integer", is_nullable => 1 },
  "maxrate",
  { data_type => "integer", is_nullable => 1 },
  "txrate",
  { data_type => "integer", is_nullable => 1 },
  "sigstrength",
  { data_type => "integer", is_nullable => 1 },
  "sigqual",
  { data_type => "integer", is_nullable => 1 },
  "rxpkt",
  { data_type => "integer", is_nullable => 1 },
  "txpkt",
  { data_type => "integer", is_nullable => 1 },
  "rxbyte",
  { data_type => "bigint", is_nullable => 1 },
  "txbyte",
  { data_type => "bigint", is_nullable => 1 },
  "time_last",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
  "ssid",
  { data_type => "text", is_nullable => 0, default_value => '' },
);
__PACKAGE__->set_primary_key("mac", "ssid");


# Created by DBIx::Class::Schema::Loader v0.07015 @ 2012-01-07 14:20:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:3xsSiWzL85ih3vhdews8Hg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
