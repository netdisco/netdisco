package App::Netdisco::DB::ResultSet::NodeWireless;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings FATAL => 'all';

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::ExplicitLocking
/);

1;
