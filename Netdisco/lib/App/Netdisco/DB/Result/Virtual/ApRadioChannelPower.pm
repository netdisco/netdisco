package App::Netdisco::DB::Result::Virtual::ApRadioChannelPower;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('ap_radio_channel_power');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
  SELECT distinct d.name as device_name, d.ip, d.dns, d.model, d.location,
      dp.port, dp.name as port_name, dp.descr, w.channel, w.power
    FROM device AS d, device_port_wireless AS w, device_port AS dp
    WHERE dp.port = w.port AND d.ip = w.ip
    ORDER BY d.name
ENDSQL
);

__PACKAGE__->add_columns(
  'device_name' => {
    data_type => 'text',
  },
  'ip' => {
    data_type => 'inet',
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
  'port' => {
    data_type => 'text',
  },
  'port_name' => {
    data_type => 'text',
  },
  'descr' => {
    data_type => 'text',
  },
  'channel' => {
    data_type => 'integer',
  },
  'power' => {
    data_type => 'integer',
  },
);

1;
