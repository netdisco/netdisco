package App::Netdisco::DB::Result::Virtual::PortVLANMismatch;

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('port_vlan_mismatch');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
  WITH all_vlans AS
    (SELECT ip, port,
            array_to_string(array_agg( CASE WHEN native THEN 'n:' || vlan::text
                                        ELSE vlan::text END
                       ORDER BY vlan ASC ), ', ') AS vlist 
     FROM device_port_vlan GROUP BY ip, port)

  SELECT CASE WHEN length(ld.dns) > 0 THEN ld.dns ELSE host(ld.ip) END AS left_device,
         lp.port AS left_port,
         (SELECT vlist FROM all_vlans WHERE ip=lp.ip AND port=lp.port) AS left_vlans,
         CASE WHEN length(rd.dns) > 0 THEN rd.dns ELSE host(rd.ip) END AS right_device,
         rp.port AS right_port,
         (SELECT vlist FROM all_vlans WHERE ip=rp.ip AND port=rp.port) AS right_vlans
  FROM device ld
       JOIN device_port lp USING (ip)
       JOIN device_port rp ON lp.remote_ip=rp.ip AND lp.remote_port=rp.port
       JOIN device rd ON rp.ip=rd.ip
  WHERE ld.ip < rd.ip AND
        (SELECT vlist FROM all_vlans WHERE ip=lp.ip AND port=lp.port)
        !=
        (SELECT vlist FROM all_vlans WHERE ip=rp.ip AND port=rp.port)
  ORDER BY left_device, left_port
ENDSQL

__PACKAGE__->add_columns(
  'left_device'  => { data_type => 'text' },
  'left_port'    => { data_type => 'text' },
  'left_vlans'   => { data_type => 'text' },

  'right_device' => { data_type => 'text' },
  'right_port'   => { data_type => 'text' },
  'right_vlans'  => { data_type => 'text' },
);

1;
