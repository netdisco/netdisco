package App::Netdisco::DB::Result::Virtual::PortVLANMismatch;

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('port_vlan_mismatch');
__PACKAGE__->result_source_instance->is_virtual(1);
my $all_vlans = qq/
SELECT ip, port,
            array_to_string(array_agg( CASE WHEN native THEN 'n:' || vlan::text
                                        ELSE vlan::text END
                       ORDER BY vlan ASC ), ', ') AS vlist 
     FROM (SELECT ip, port, native, vlan FROM device_port_vlan UNION
            SELECT dp.ip, dp.port, false, dp2v.vlan
                FROM device_port dp
            LEFT JOIN device_port dp2 ON (dp.ip = dp2.ip and dp.port = dp2.slave_of)
            LEFT JOIN device_port_vlan dp2v ON (dp2.ip = dp2v.ip and dp2.port = dp2v.port)
                WHERE dp.has_subinterfaces) alldpv
     WHERE vlan::text NOT IN (?, ?, ?, ?) GROUP BY ip, port
/;
__PACKAGE__->result_source_instance->view_definition("
  SELECT CASE WHEN length(ld.dns) > 0 THEN ld.dns ELSE host(ld.ip) END AS left_device,
         ld.name AS left_name,
         lp.port AS left_port,
         lp.name AS left_portname,
         (SELECT vlist FROM ($all_vlans) a0 WHERE ip=lp.ip AND port=lp.port) AS left_vlans,
         CASE WHEN length(rd.dns) > 0 THEN rd.dns ELSE host(rd.ip) END AS right_device,
         rd.name AS right_name,
         rp.port AS right_port,
         rp.name AS right_portname,
         (SELECT vlist FROM ($all_vlans) a1 WHERE ip=rp.ip AND port=rp.port) AS right_vlans
  FROM device ld 
       JOIN device_port lp USING (ip)
       JOIN device_port rp ON lp.remote_ip=rp.ip AND lp.remote_port=rp.port
       JOIN device rd ON rp.ip=rd.ip
  WHERE ld.ip < rd.ip AND
        (SELECT vlist FROM ($all_vlans) a2 WHERE ip=lp.ip AND port=lp.port)
        !=
        (SELECT vlist FROM ($all_vlans) a3 WHERE ip=rp.ip AND port=rp.port)
  ORDER BY left_device, left_port
");

__PACKAGE__->add_columns(
  'left_device'   => { data_type => 'text' },
  'left_name'     => { data_type => 'text' },
  'left_port'     => { data_type => 'text' },
  'left_portname' => { data_type => 'text' },
  'left_vlans'    => { data_type => 'text' },

  'right_device'   => { data_type => 'text' },
  'right_name'     => { data_type => 'text' },
  'right_port'     => { data_type => 'text' },
  'right_portname' => { data_type => 'text' },
  'right_vlans'    => { data_type => 'text' },
);

1;
