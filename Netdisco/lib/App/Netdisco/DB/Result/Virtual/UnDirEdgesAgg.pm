package App::Netdisco::DB::Result::Virtual::UnDirEdgesAgg;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('undir_edges_agg');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
   SELECT left_ip,
          array_agg(right_ip) AS links
   FROM
     ( SELECT dp.ip AS left_ip,
              di.ip AS right_ip
      FROM
        (SELECT device_port.ip,
                device_port.remote_ip
         FROM device_port
         WHERE device_port.remote_port IS NOT NULL
         GROUP BY device_port.ip,
                  device_port.remote_ip) dp
      LEFT JOIN device_ip di ON dp.remote_ip = di.alias
      WHERE di.ip IS NOT NULL
      UNION SELECT di.ip AS left_ip,
                   dp.ip AS right_ip
      FROM
        (SELECT device_port.ip,
                device_port.remote_ip
         FROM device_port
         WHERE device_port.remote_port IS NOT NULL
         GROUP BY device_port.ip,
                  device_port.remote_ip) dp
      LEFT JOIN device_ip di ON dp.remote_ip = di.alias
      WHERE di.ip IS NOT NULL ) AS foo
   GROUP BY left_ip
   ORDER BY left_ip
ENDSQL

__PACKAGE__->add_columns(
  'left_ip' => {
    data_type => 'inet',
  },
  'links' => {
    data_type => 'inet[]',
  }
);

__PACKAGE__->belongs_to('device', 'App::Netdisco::DB::Result::Device',
  { 'foreign.ip' => 'self.left_ip' });

1;
