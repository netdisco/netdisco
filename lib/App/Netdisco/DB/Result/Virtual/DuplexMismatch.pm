package App::Netdisco::DB::Result::Virtual::DuplexMismatch;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('duplex_mismatch');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
 SELECT dp.ip AS left_ip, d1.dns AS left_dns, dp.port AS left_port, dp.duplex AS left_duplex,
        di.ip AS right_ip, d2.dns AS right_dns, dp.remote_port AS right_port, dp2.duplex AS right_duplex
   FROM ( SELECT device_port.ip, device_port.remote_ip, device_port.port, device_port.duplex, device_port.remote_port
           FROM device_port
          WHERE
            device_port.remote_port IS NOT NULL
            AND device_port.up NOT ILIKE '%down%'
          GROUP BY device_port.ip, device_port.remote_ip, device_port.port, device_port.duplex, device_port.remote_port
          ORDER BY device_port.ip) dp
   LEFT JOIN device_ip di ON dp.remote_ip = di.alias
   LEFT JOIN device d1 ON dp.ip = d1.ip
   LEFT JOIN device d2 ON di.ip = d2.ip
   LEFT JOIN device_port dp2 ON (di.ip = dp2.ip AND dp.remote_port = dp2.port)
  WHERE di.ip IS NOT NULL
   AND dp.duplex <> dp2.duplex
   AND dp.ip <= di.ip
   AND dp2.up NOT ILIKE '%down%'
  ORDER BY dp.ip
ENDSQL
);

__PACKAGE__->add_columns(
  'left_ip' => {
    data_type => 'inet',
  },
  'left_dns' => {
    data_type => 'text',
  },
  'left_port' => {
    data_type => 'text',
  },
  'left_duplex' => {
    data_type => 'text',
  },
  'right_ip' => {
    data_type => 'inet',
  },
  'right_dns' => {
    data_type => 'text',
  },
  'right_port' => {
    data_type => 'text',
  },
  'right_duplex' => {
    data_type => 'text',
  },
);

1;
