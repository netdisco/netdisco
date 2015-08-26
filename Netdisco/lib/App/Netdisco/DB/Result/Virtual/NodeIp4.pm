use utf8;
package App::Netdisco::DB::Result::Virtual::NodeIp4;

use strict;
use warnings;

use base 'App::Netdisco::DB::Result::NodeIp';

__PACKAGE__->load_components('Helper::Row::SubClass');
__PACKAGE__->subclass;

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table("node_ip4");
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(q{
  SELECT * FROM node_ip WHERE family(ip) = 4
});

1;
