package App::Netdisco::DB::Result::Virtual::DeviceLinks;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

# note to future devs:
# this query does not use the slave_of field in device_port table to group
# ports because what we actually want is total b/w between devices on all
# links, regardless of whether those links are in an aggregate.

__PACKAGE__->table('device_links');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
 SELECT dp.ip AS left_ip, array_agg(dp.port) AS left_port, array_agg(dp.name) AS left_descr,
        sum(btrim(dp.speed, ' MGTbps')::float
          * (CASE btrim(dp.speed, ' 0123456789.')
               WHEN 'Gbps' THEN 1000
               WHEN 'Tbps' THEN 1000000
               ELSE 1 END)) AS aggspeed,
        count(*) AS aggports,
        dp2.ip AS right_ip, array_agg(dp2.port) AS right_port, array_agg(dp2.name) AS right_descr

 FROM device_port dp
 INNER JOIN device_ip di ON dp.remote_ip = di.alias
 INNER JOIN device_port dp2 ON (di.ip = dp2.ip AND dp.remote_port = dp2.port)

 WHERE dp.remote_port IS NOT NULL
   AND dp.type = 'ethernetCsmacd'
   AND dp.speed LIKE '%bps'
   AND dp.ip <= dp2.ip
 GROUP BY left_ip, right_ip
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
