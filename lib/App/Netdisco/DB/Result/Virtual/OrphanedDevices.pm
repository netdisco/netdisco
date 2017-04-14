package App::Netdisco::DB::Result::Virtual::OrphanedDevices;

use strict;
use warnings;

use utf8;
use base 'App::Netdisco::DB::Result::Device';

__PACKAGE__->load_components('Helper::Row::SubClass');
__PACKAGE__->subclass;

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table('orphaned_devices');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
SELECT *
FROM device
WHERE ip NOT IN
    ( SELECT DISTINCT dp.ip AS ip
     FROM
       (SELECT device_port.ip,
               device_port.remote_ip
        FROM device_port
        WHERE device_port.remote_port IS NOT NULL
        GROUP BY device_port.ip,
                 device_port.remote_ip
        ORDER BY device_port.ip) dp
     LEFT JOIN device_ip di ON dp.remote_ip = di.alias
     WHERE di.ip IS NOT NULL)
ENDSQL

1;
