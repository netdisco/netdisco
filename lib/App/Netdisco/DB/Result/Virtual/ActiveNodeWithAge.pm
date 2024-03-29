use utf8;
package App::Netdisco::DB::Result::Virtual::ActiveNodeWithAge;

use strict;
use warnings;

use base 'App::Netdisco::DB::Result::Virtual::ActiveNode';

__PACKAGE__->load_components('Helper::Row::SubClass');
__PACKAGE__->subclass;

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table("active_node_with_age");
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(q{
  SELECT *,
    replace( date_trunc( 'minute', age( LOCALTIMESTAMP, time_last + interval '30 second' ) ) ::text, 'mon', 'month')
      AS time_last_age
  FROM node WHERE active
});

__PACKAGE__->add_columns(
  "time_last_age",
  { data_type => "text", is_nullable => 1 },
);

1;
