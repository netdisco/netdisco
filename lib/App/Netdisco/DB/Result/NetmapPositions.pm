use utf8;
package App::Netdisco::DB::Result::NetmapPositions;

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("netmap_positions");
__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_nullable => 0, is_auto_increment => 1 },
  "device_groups",
  { data_type => "text[]", is_nullable => 0 },
  "positions",
  { data_type => "text", is_nullable => 0 },
);

__PACKAGE__->set_primary_key("id");

__PACKAGE__->add_unique_constraint(
  "netmap_positions_device_groups_key" => ['device_groups']);

1;
