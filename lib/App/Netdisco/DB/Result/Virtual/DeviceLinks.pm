package App::Netdisco::DB::Result::Virtual::DeviceLinks;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('device_links');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
 SELECT dp.ip AS left_ip, dp.port AS left_port, dp.name AS left_descr,
        dp.speed,
        dp2.ip AS right_ip, dp2.port AS right_port, dp2.name AS right_descr
   FROM ( SELECT device_port.ip, device_port.port, device_port.name,
                 device_port.speed,
                 device_port.remote_ip, device_port.remote_port
           FROM device_port
          WHERE device_port.remote_port IS NOT NULL
            AND device_port.type = 'ethernetCsmacd' ) dp
   INNER JOIN device_ip di ON dp.remote_ip = di.alias
   INNER JOIN device_port dp2 ON (di.ip = dp2.ip AND dp.remote_port = dp2.port)
 WHERE dp.ip <= dp2.ip
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
  'left_descr' => {
    data_type => 'text',
  },
  'speed' => {
    data_type => 'text',
  },
  'right_ip' => {
    data_type => 'inet',
  },
  'right_port' => {
    data_type => 'text',
  },
  'right_descr' => {
    data_type => 'text',
  },
);

__PACKAGE__->has_many('left_vlans', 'App::Netdisco::DB::Result::DevicePortVlan',
  { 'foreign.ip' => 'self.left_ip', 'foreign.port' => 'self.left_port' });

__PACKAGE__->has_many('right_vlans', 'App::Netdisco::DB::Result::DevicePortVlan',
  { 'foreign.ip' => 'self.right_ip', 'foreign.port' => 'self.right_port' });

1;
