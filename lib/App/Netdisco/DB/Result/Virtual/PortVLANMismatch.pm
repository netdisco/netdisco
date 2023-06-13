package App::Netdisco::DB::Result::Virtual::PortVLANMismatch;

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('port_vlan_mismatch');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');

SELECT  ips[1] AS left_ip,
        ld.dns AS left_dns,
        ports[1] AS left_port,
        port_descr[1] AS left_port_descr,

        (SELECT array_agg(a) FROM jsonb_array_elements_text(vlans->0) AS a) AS left_vlans,
        (SELECT array_agg(a)
            FROM jsonb_array_elements_text(vlans->0) AS a
            WHERE a NOT IN
                (SELECT b FROM jsonb_array_elements_text(vlans->1) AS b)) as only_left_vlans,

        ips[2] AS right_ip,
        rd.dns AS right_dns,
        ports[2] AS right_port,
        port_descr[2] AS right_port_descr,

        (SELECT array_agg(a) FROM jsonb_array_elements_text(vlans->1) AS a) AS right_vlans,
        (SELECT array_agg(a)
            FROM jsonb_array_elements_text(vlans->1) AS a
            WHERE a NOT IN
                (SELECT b FROM jsonb_array_elements_text(vlans->0) AS b)) as only_right_vlans,

        CASE WHEN (jsonb_array_length(vlans->0) = 1 AND jsonb_array_length(vlans->1) = 1
                   AND position('n:' in vlans->0->>0) = 1 AND position('n:' in vlans->1->>0) = 1)
             THEN true ELSE false END AS native_translated

FROM (
    SELECT array_agg(ip) AS ips,
           array_agg(port) AS ports,
           array_agg(port_descr) AS port_descr,
           jsonb_agg(DISTINCT vlist) AS vlans

    FROM (
        SELECT alldpv.ip,
               alldpv.port,
               alldpv.port_descr,
               jsonb_agg( CASE WHEN native THEN 'n:' || vlan::text ELSE vlan::text END ORDER BY vlan ASC )
                   FILTER (WHERE vlan IS NOT NULL) AS vlist,
               -- create a key for each port allowing pairs of ports to be matched
               CASE WHEN alldpv.ip <= alldpv.remote_ip THEN host(alldpv.ip)::text || '!' || alldpv.port::text
                    ELSE host(alldpv.remote_ip)::text || '!' || alldpv.remote_port::text END AS lowport

        FROM (
            SELECT dpv.ip, dpv.port, dp.name as port_descr, dpv.native, dip.ip AS remote_ip, dp.remote_port, dpv.vlan
            FROM device_port_vlan dpv

            LEFT JOIN device_port dp
                ON dpv.ip = dp.ip AND dpv.port = dp.port

            LEFT JOIN device_ip dip
                ON dp.remote_ip = dip.alias

            UNION

            SELECT dp2.ip, dp2.port, dp2.name AS port_descr, false, dip2.ip AS remote_ip, dp2.remote_port, dpv2.vlan
            FROM device_port dp2

            LEFT JOIN device_port dp3
                ON dp2.ip = dp3.ip AND dp2.port = dp3.slave_of AND dp2.has_subinterfaces

            LEFT JOIN device_port_vlan dpv2
                ON dp3.ip = dpv2.ip AND dp3.port = dpv2.port

            LEFT JOIN device_ip dip2
                ON dp2.remote_ip = dip2.alias
        ) alldpv

        WHERE vlan NOT IN ( ?, ?, ?, ? ) AND remote_ip IS NOT NULL
        GROUP BY ip, port, port_descr, remote_ip, remote_port
    ) ports_with_vlans

    GROUP BY lowport
) pairs_of_ports

LEFT JOIN device ld ON ips[1] = ld.ip
LEFT JOIN device rd ON ips[2] = rd.ip

WHERE jsonb_array_length(vlans) > 1
ORDER BY left_ip, left_port

ENDSQL

__PACKAGE__->add_columns(
  'left_ip'         => { data_type => 'text' },
  'left_dns'        => { data_type => 'text' },
  'left_port'       => { data_type => 'text' },
  'left_port_descr' => { data_type => 'text' },
  'left_vlans'      => { data_type => 'text[]' },
  'only_left_vlans' => { data_type => 'text[]' },

  'right_ip'         => { data_type => 'text' },
  'right_dns'        => { data_type => 'text' },
  'right_port'       => { data_type => 'text' },
  'right_port_descr' => { data_type => 'text' },
  'right_vlans'      => { data_type => 'text[]' },
  'only_right_vlans' => { data_type => 'text[]' },
);

1;
