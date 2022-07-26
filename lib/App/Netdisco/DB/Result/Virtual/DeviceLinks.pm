package App::Netdisco::DB::Result::Virtual::DeviceLinks;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

# note to future devs:
# this query does not use the slave_of field in device_port table to group
# ports because what we actually want is total b/w between devices on all
# links, regardless of whether those links are in an aggregate.

__PACKAGE__->table('device_links');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
  WITH BothWays AS
    ( SELECT ldp.ip AS left_ip,
             ld.dns AS left_dns,
             ld.name AS left_name,
             array_agg(ldp.port ORDER BY ldp.port) AS left_port,
             array_agg(ldp.name ORDER BY ldp.name) AS left_descr,

             count(ldpp.*) AS aggports,
             sum(COALESCE(ldpp.raw_speed, 0)) AS aggspeed,

             di.ip AS right_ip,
             rd.dns AS right_dns,
             rd.name AS right_name,
             array_agg(ldp.remote_port ORDER BY ldp.remote_port) AS right_port,
             array_agg(rdp.name ORDER BY rdp.name) AS right_descr

     FROM device_port ldp

     LEFT OUTER JOIN device_port_properties ldpp ON (
        (ldp.ip = ldpp.ip) AND (ldp.port = ldpp.port)
        AND (ldp.type IS NULL
             OR ldp.type !~* '^(53|ieee8023adLag|propVirtual|l2vlan|l3ipvlan|135|136|137)\$')
        AND (ldp.is_master = 'false'
             OR ldp.slave_of IS NOT NULL) )

     INNER JOIN device ld ON ldp.ip = ld.ip
     INNER JOIN
      (SELECT ip, alias FROM device_ip WHERE alias IN
        (SELECT alias FROM device_ip GROUP BY alias HAVING count(alias) = 1)) di
        ON ldp.remote_ip = di.alias
     INNER JOIN device rd ON di.ip = rd.ip

     LEFT OUTER JOIN device_port rdp ON (di.ip = rdp.ip
                                         AND ((ldp.remote_port = rdp.port)
                                              OR (ldp.remote_port = rdp.name)
                                              OR (ldp.remote_port = rdp.descr)))

     WHERE ldp.remote_port IS NOT NULL
       AND ldp.port !~* 'vlan'
       AND (ldp.descr IS NULL OR ldp.descr !~* 'vlan')

     GROUP BY left_ip,
              left_dns,
              left_name,
              right_ip,
              right_dns,
              right_name )

  SELECT *
  FROM BothWays b
  WHERE NOT EXISTS
      ( SELECT *
       FROM BothWays b2
       WHERE b2.right_ip = b.left_ip
         AND b2.right_port = b.left_port
         AND b2.left_ip < b.left_ip )
  ORDER BY aggspeed DESC, 1, 2
ENDSQL
);

__PACKAGE__->add_columns(
  'left_ip' => {
    data_type => 'inet',
  },
  'left_dns' => {
    data_type => 'text',
  },
  'left_name' => {
    data_type => 'text',
  },
  'left_port' => {
    data_type => '[text]',
  },
  'left_descr' => {
    data_type => '[text]',
  },
  'aggspeed' => {
    data_type => 'bigint',
  },
  'aggports' => {
    data_type => 'integer',
  },
  'right_ip' => {
    data_type => 'inet',
  },
  'right_dns' => {
    data_type => 'text',
  },
  'right_name' => {
    data_type => 'text',
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
