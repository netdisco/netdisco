package App::Netdisco::DB::Result::Virtual::DevicePortSpeed;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('device_port_speed');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
  SELECT ip,
         sum(btrim(speed, ' MGTbps')::float *
           (CASE btrim(speed, ' 0123456789.')
            WHEN 'Gbps' THEN 1000
            WHEN 'Tbps' THEN 1000000
            ELSE 1 END)) AS total
  FROM device_port
  WHERE type = 'ethernetCsmacd'
    AND speed LIKE '%bps'
  GROUP BY ip
  ORDER BY total DESC
ENDSQL
);

__PACKAGE__->add_columns(
  'total' => {
    data_type => 'integer',
  },
);

__PACKAGE__->belongs_to('device', 'App::Netdisco::DB::Result::Device',
  { 'foreign.ip' => 'self.ip' });

1;
