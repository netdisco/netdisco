package App::Netdisco::DB::Result;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->load_components(qw{Helper::Row::ToJSON});

# for DBIx::Class::Helper::Row::ToJSON
# to allow text columns to be included in results

sub unserializable_data_types {
   return {
      blob  => 1,
      ntext => 1,
   };
}

1;
