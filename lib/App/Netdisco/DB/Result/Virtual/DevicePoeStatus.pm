package App::Netdisco::DB::Result::Virtual::DevicePoeStatus;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('device_poe_status');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
SELECT DISTINCT ON (dp.ip,dp.module)
       dp.ip,
       dp.module,
       dp.power::bigint,
       dp.status,
       d.dns,
       d.name,
       d.model,
       d.location,
       COUNT(dpp.port) OVER (PARTITION BY dp.ip, dp.module) AS poe_capable_ports,
       SUM(CASE WHEN dpp.status = 'deliveringPower' THEN 1 ELSE 0 END) OVER (PARTITION BY dp.ip, dp.module) AS poe_powered_ports,
       SUM(CASE WHEN dpp.admin = 'false' THEN 1 ELSE 0 END) OVER (PARTITION BY dp.ip, dp.module) AS poe_disabled_ports,
       SUM(CASE WHEN dpp.status ILIKE '%fault' THEN 1 
                ELSE 0 END) OVER (PARTITION BY dp.ip, dp.module) AS poe_errored_ports,
       SUM(CASE WHEN dpp.status = 'deliveringPower' AND dpp.class = 'class4' THEN 30.0 
                WHEN dpp.status = 'deliveringPower' AND dpp.class = 'class2' THEN 7.0 
                WHEN dpp.status = 'deliveringPower' AND dpp.class = 'class1' THEN 4.0 
                WHEN dpp.status = 'deliveringPower' AND dpp.class = 'class3' THEN 15.4
                WHEN dpp.status = 'deliveringPower' AND dpp.class = 'class0' THEN 15.4
                WHEN dpp.status = 'deliveringPower' AND dpp.class IS NULL THEN 15.4
                ELSE 0 END) OVER (PARTITION BY dp.ip, dp.module) AS poe_power_committed,
       SUM(CASE WHEN (dpp.power IS NULL OR dpp.power = '0') THEN 0
           ELSE round(dpp.power/1000.0, 1) END) OVER (PARTITION BY dp.ip, dp.module) AS poe_power_delivering
FROM device_power dp
JOIN device_port_power dpp ON dpp.ip = dp.ip
AND dpp.module = dp.module
JOIN device d ON dp.ip = d.ip
ENDSQL

__PACKAGE__->add_columns(
  'ip' => {
    data_type => 'inet',
  },
  'module' => {
    data_type => 'integer',
  },
  'power' => {
    data_type => 'integer',
  },
  'status' => {
    data_type => 'text',
  },
  'dns' => {
    data_type => 'text',
  },
  'name' => {
    data_type => 'text',
  },
  'model' => {
    data_type => 'text',
  },
  'location' => {
    data_type => 'text',
  },
  'poe_capable_ports' => {
    data_type => 'bigint',
  },
  'poe_powered_ports' => {
    data_type => 'bigint',
  },
  'poe_disabled_ports' => {
    data_type => 'bigint',
  },
  'poe_errored_ports' => {
    data_type => 'bigint',
  },
  'poe_power_committed' => {
    data_type => 'numeric',
  },
  'poe_power_delivering' => {
    data_type => 'numeric',
  },
);

1;
