use utf8;
package App::Netdisco::DB::Result::Enterprise;

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("enterprise");

__PACKAGE__->add_columns(
  "enterprise_number",
  { data_type => "integer", is_nullable => 0 },
  "organization",
  { data_type => "text", is_nullable => 0 },
);

__PACKAGE__->set_primary_key("enterprise_number");

1;
