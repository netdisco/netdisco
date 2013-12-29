package App::Netdisco::DB::Result::Virtual::DeviceLinks;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('device_links');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
 SELECT dp.ip AS left_ip, dp.port AS left_port, di.ip AS right_ip, dp.remote_port AS right_port
   FROM ( SELECT device_port.ip, device_port.port, device_port.remote_ip, device_port.remote_port
           FROM device_port
          WHERE device_port.remote_port IS NOT NULL
          GROUP BY device_port.ip, device_port.port, device_port.remote_ip, device_port.remote_port
          ORDER BY device_port.ip) dp
   LEFT JOIN device_ip di ON dp.remote_ip = di.alias
  WHERE di.ip IS NOT NULL
  ORDER BY dp.ip
ENDSQL
);

__PACKAGE__->add_columns(
  'left_ip' => {
    data_type => 'inet',
  },
  'left_port' => {
    data_type => 'text',
  },
  'right_ip' => {
    data_type => 'inet',
  },
  'right_port' => {
    data_type => 'text',
  },
);

__PACKAGE__->has_many('left_vlans', 'App::Netdisco::DB::Result::DevicePortVlan',
  { 'foreign.ip' => 'self.left_ip', 'foreign.port' => 'self.left_port' },
  { join_type => 'INNER' } );

__PACKAGE__->has_many('right_vlans', 'App::Netdisco::DB::Result::DevicePortVlan',
  { 'foreign.ip' => 'self.right_ip', 'foreign.port' => 'self.right_port' },
  { join_type => 'INNER' } );

1;
