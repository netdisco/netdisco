use utf8;
package App::Netdisco::DB::Result::NetmapPositions;

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("netmap_positions");
__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_nullable => 0, is_auto_increment => 1 },
  "device",
  { data_type => "inet", is_nullable => 1 },
  "host_groups",
  { data_type => "text[]", is_nullable => 0 },
  "locations",
  { data_type => "text[]", is_nullable => 0 },
  "vlan",
  { data_type => "integer", is_nullable => 0, default => 0 },
  "positions",
  { data_type => "text", is_nullable => 0 },
);

__PACKAGE__->set_primary_key("id");

1;
