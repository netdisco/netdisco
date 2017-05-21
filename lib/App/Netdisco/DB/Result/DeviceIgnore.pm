use utf8;
package App::Netdisco::DB::Result::DeviceIgnore;

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("device_ignore");
__PACKAGE__->add_columns(
  "backend",
  { data_type => "text", is_nullable => 0 },
  "device",
  { data_type => "inet", is_nullable => 0 },
  "action",
  { data_type => "text", is_nullable => 0 },
  "failures",
  { data_type => "integer", is_nullable => 1, default_value => '0' },
  "ignore",
  { data_type => "boolean", is_nullable => 1, default_value => \'false' },
);
__PACKAGE__->set_primary_key("backend", "device", "action");

1;
