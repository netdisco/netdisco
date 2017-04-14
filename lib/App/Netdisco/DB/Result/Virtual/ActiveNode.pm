use utf8;
package App::Netdisco::DB::Result::Virtual::ActiveNode;

use strict;
use warnings;

use base 'App::Netdisco::DB::Result::Node';

__PACKAGE__->load_components('Helper::Row::SubClass');
__PACKAGE__->subclass;

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table("active_node");
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(q{
  SELECT * FROM node WHERE active
});

1;
