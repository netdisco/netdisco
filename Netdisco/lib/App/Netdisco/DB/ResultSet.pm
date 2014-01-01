package App::Netdisco::DB::ResultSet;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';

__PACKAGE__->load_components(
    qw{Helper::ResultSet::SetOperations Helper::ResultSet::Shortcut});

1;
