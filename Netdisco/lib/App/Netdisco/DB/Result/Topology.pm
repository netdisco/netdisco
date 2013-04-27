use utf8;
package App::Netdisco::DB::Result::Topology;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table("topology");

__PACKAGE__->add_columns(
  "dev1",
  { data_type => "inet", is_nullable => 0 },
  "port1",
  { data_type => "text", is_nullable => 0 },
  "dev2",
  { data_type => "inet", is_nullable => 0 },
  "port2",
  { data_type => "text", is_nullable => 0 },
);

__PACKAGE__->add_unique_constraint(['dev1','port1']);
__PACKAGE__->add_unique_constraint(['dev2','port2']);

1;
