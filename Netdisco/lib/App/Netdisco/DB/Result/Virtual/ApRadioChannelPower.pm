package App::Netdisco::DB::Result::Virtual::ApRadioChannelPower;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('ap_radio_channel_power');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
SELECT w.channel,
       w.power,
       w.ip,
       w.port,
       dp.name AS port_name,
       dp.descr,
       d.name AS device_name,
       d.dns,
       d.model,
       d.location,
       CASE
           WHEN w.power > 0 THEN round((10.0 * log(w.power) / log(10))::numeric, 1)
           ELSE NULL
       END AS power2
FROM device_port_wireless AS w
JOIN device_port AS dp ON dp.port = w.port
AND dp.ip = w.ip
JOIN device AS d ON d.ip = w.ip
WHERE w.channel != '0'
ENDSQL
);

__PACKAGE__->add_columns(
  'channel' => {
    data_type => 'integer',
  },
  'power' => {
    data_type => 'integer',
  },
  'ip' => {
    data_type => 'inet',
  },
  'port' => {
    data_type => 'text',
  },
  'port_name' => {
    data_type => 'text',
  },
  'descr' => {
    data_type => 'text',
  },
  'device_name' => {
    data_type => 'text',
  },
  'dns' => {
    data_type => 'text',
  },
  'model' => {
    data_type => 'text',
  },
  'location' => {
    data_type => 'text',
  },
  'power2' => {
    data_type => 'numeric',
  },
);

1;
