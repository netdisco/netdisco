package App::Netdisco::DB::Result::Virtual::DeviceLinks;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

# notes to future devs:

# this query does not use the slave_of field in device_port table to group
# ports because what we actually want is total b/w between devices on all
# links, regardless of whether those links are in an aggregate.

# PG 8.4 does not have sorting within an aggregate so we cannot ensure that
# left and right ports and names correspond within arrays. this is why the
# right ports are the left's remote_ports (and right_descr should be ignored)

__PACKAGE__->table('device_links');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
 SELECT dp.ip AS left_ip, dp.ports AS left_port, dp.descriptions AS left_descr,
        dp.speed AS aggspeed, dp.aggports,
        dp2.ip AS right_ip, dp.remote_ports AS right_port, array_agg(dp2.name) AS right_descr

   FROM ( SELECT device_port.ip, device_port.remote_ip,
                 array_agg(device_port.port) as ports,
                 array_agg(device_port.name) as descriptions,
                 array_agg(device_port.remote_port) as remote_ports,
                 count(*) AS aggports,
                 sum(btrim(device_port.speed, ' MGTbps')::float
                   * (CASE btrim(device_port.speed, ' 0123456789.')
                        WHEN 'Gbps' THEN 1000
                        WHEN 'Tbps' THEN 1000000
                        ELSE 1 END)) AS speed
           FROM device_port
          WHERE device_port.remote_port IS NOT NULL
            AND device_port.type = 'ethernetCsmacd'
            AND device_port.speed LIKE '%bps'
          GROUP BY device_port.ip, device_port.remote_ip) dp

   INNER JOIN device_ip di ON dp.remote_ip = di.alias
   INNER JOIN device_port dp2 ON (di.ip = dp2.ip AND dp.remote_ports @> ARRAY[dp2.port])
 WHERE dp.ip <= dp2.ip
 GROUP BY left_ip, left_port, left_descr, aggspeed, aggports, right_ip, right_port
 ORDER BY dp.ip
ENDSQL
);

__PACKAGE__->add_columns(
  'left_ip' => {
    data_type => 'inet',
  },
  'left_port' => {
    data_type => '[text]',
  },
  'left_descr' => {
    data_type => '[text]',
  },
  'aggspeed' => {
    data_type => 'integer',
  },
  'aggports' => {
    data_type => 'integer',
  },
  'right_ip' => {
    data_type => 'inet',
  },
  'right_port' => {
    data_type => '[text]',
  },
  'right_descr' => {
    data_type => '[text]',
  },
);

__PACKAGE__->has_many('left_vlans', 'App::Netdisco::DB::Result::DevicePortVlan',
  sub {
    my $args = shift;
    return {
      "$args->{foreign_alias}.ip" => { -ident => "$args->{self_alias}.left_ip" },
      "$args->{self_alias}.left_port" => { '@>' => \"ARRAY[$args->{foreign_alias}.port]" },
    };
  }
);

__PACKAGE__->has_many('right_vlans', 'App::Netdisco::DB::Result::DevicePortVlan',
  sub {
    my $args = shift;
    return {
      "$args->{foreign_alias}.ip" => { -ident => "$args->{self_alias}.right_ip" },
      "$args->{self_alias}.right_port" => { '@>' => \"ARRAY[$args->{foreign_alias}.port]" },
    };
  }
);

1;
