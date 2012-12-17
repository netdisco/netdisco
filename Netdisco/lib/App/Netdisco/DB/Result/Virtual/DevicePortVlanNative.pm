use utf8;
package App::Netdisco::DB::Result::Virtual::DevicePortVlanNative;

use strict;
use warnings;

use base 'App::Netdisco::DB::Result::DevicePortVlan';

__PACKAGE__->load_components('Helper::Row::SubClass');
__PACKAGE__->subclass;

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table("device_port_vlan_native");
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(q{
  SELECT * FROM device_port_vlan WHERE native
});

1;
