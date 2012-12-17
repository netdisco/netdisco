use utf8;
package App::Netdisco::DB::Result::NodeMonitor;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("node_monitor");
__PACKAGE__->add_columns(
  "mac",
  { data_type => "macaddr", is_nullable => 0 },
  "active",
  { data_type => "boolean", is_nullable => 1 },
  "why",
  { data_type => "text", is_nullable => 1 },
  "cc",
  { data_type => "text", is_nullable => 1 },
  "date",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
);
__PACKAGE__->set_primary_key("mac");


# Created by DBIx::Class::Schema::Loader v0.07015 @ 2012-01-07 14:20:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:0prRdz2XYlFuE+nahsI2Yg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
