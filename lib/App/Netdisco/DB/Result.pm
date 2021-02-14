package App::Netdisco::DB::Result;

use strict;
use warnings;

use base 'DBIx::Class::Core';

BEGIN {
  no warnings 'redefine';
  __PACKAGE__->load_components(qw{Helper::Row::ToJSON});

  # this replacement will avoid the issue of relation names which override
  # field names, causing TO_JSON to return object instances, breaking to_json
  *DBIx::Class::Helper::Row::ToJSON::TO_JSON = sub {
      my $self = shift;
      my $columns_info = $self->columns_info($self->serializable_columns);
      my $columns_data = { $self->get_columns };
      return {
         map +($_ => $columns_data->{$_}), keys %$columns_info
      };
  };
}

# for DBIx::Class::Helper::Row::ToJSON
# to allow text columns to be included in results

sub unserializable_data_types {
   return {
      blob  => 1,
      ntext => 1,
   };
}

1;
