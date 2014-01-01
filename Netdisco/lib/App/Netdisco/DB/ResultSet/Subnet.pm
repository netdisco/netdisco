package App::Netdisco::DB::ResultSet::Subnet;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings FATAL => 'all';

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::ExplicitLocking
/);

1;
