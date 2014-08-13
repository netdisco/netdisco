package App::Netdisco::DB::Result::Virtual::DevicePortFlattened;

use strict;
use warnings;

use utf8;
use base 'App::Netdisco::DB::Result::DevicePort';

__PACKAGE__->load_components('Helper::Row::SubClass');
__PACKAGE__->subclass;

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table('device_port_flattened');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
SELECT
    dp.*,
    to_char(d.last_discover - (d.uptime - dp.lastchange) / 100 * interval '1 second', 'YYYY-MM-DD HH24:MI:SS') AS lastchange_stamp,
    agg_master.up_admin AS agg_master_up_admin,
    agg_master.up AS agg_master_up,
    (SELECT array_agg(dpv.vlan) FROM device_port_vlan dpv WHERE dpv.ip = dp.ip AND dpv.port = dp.port) AS vlan_membership,
    (SELECT dpv.vlan FROM device_port_vlan dpv WHERE dpv.ip = dp.ip AND dpv.port = dp.port AND native) AS native_vlan,
    (SELECT array_agg(ssid.ssid) FROM device_port_ssid ssid WHERE ssid.ip = dp.ip AND ssid.port = dp.port) AS ssids,
    neighbor_alias.ip AS neighbor_alias_ip,
    neighbor_alias.dns AS neighbor_alias_dns,
    d.uptime AS device_uptime,
    d.last_discover AS device_last_discover,
    dpp.admin AS power_admin,
    dpp.status AS power_status,
    dpp.power AS power
FROM device_port dp
JOIN device d ON d.ip = dp.ip
LEFT JOIN device_port agg_master ON agg_master.ip = dp.ip
  AND agg_master.port = dp.slave_of
LEFT JOIN device_ip neighbor_alias ON neighbor_alias.alias = dp.remote_ip
LEFT JOIN device_port_power dpp ON dp.ip = dpp.ip
  AND dp.port = dpp.port
ENDSQL

__PACKAGE__->add_columns(
  "lastchange_stamp",
  { data_type => "text", is_nullable => 1 },
  "agg_master_up_admin",
  { data_type => "text", is_nullable => 1 },
  "agg_master_up",
  { data_type => "text", is_nullable => 1 },
  "vlan_membership",
  { data_type => "integer[]", is_nullable => 1 },
  "native_vlan",
  { data_type => "integer", is_nullable => 1 },
  "ssids",
  { data_type => "text[]", is_nullable => 1 },
  "neighbor_alias_ip",
  { data_type => "inet", is_nullable => 0 },
  "neighbor_alias_dns",
  { data_type => "text", is_nullable => 1 },
  "device_uptime",
  { data_type => "bigint", is_nullable => 1 },
  "device_last_discover",
  { data_type => "timestamp", is_nullable => 1 },
  "power_admin",
  { data_type => "text", is_nullable => 1 },
  "power_status",
  { data_type => "text", is_nullable => 1 },
  "power",
  { data_type => "integer", is_nullable => 1 },
);

__PACKAGE__->has_many( nodes => 'App::Netdisco::DB::Result::Virtual::NodeFlattened',
  {
    'foreign.switch' => 'self.ip',
    'foreign.port' => 'self.port',
  },
  { join_type => 'LEFT',
    where => { 'foreign.switch' => 'self.ip' }
  },
);

1;
