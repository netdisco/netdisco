package App::Netdisco::DB::Result::Virtual::DevicePortSpeed;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('device_port_speed');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
  SELECT ip,
         GREATEST(1, sum( COALESCE(dpp.raw_speed,1) )) as total
  FROM device_port
  LEFT OUTER JOIN device_port_properties dpp USING (ip, port)
  WHERE port !~* 'vlan'
    AND (descr IS NULL OR descr !~* 'vlan')
    AND (type IS NULL OR type !~* '^(53|ieee8023adLag|propVirtual|l2vlan|l3ipvlan|135|136|137)\$')
    AND (is_master = 'false' OR slave_of IS NOT NULL)
  GROUP BY ip
  ORDER BY total DESC, ip ASC
ENDSQL
);

__PACKAGE__->add_columns(
  'total' => {
    data_type => 'integer',
  },
);

__PACKAGE__->belongs_to('device', 'App::Netdisco::DB::Result::Device',
  { 'foreign.ip' => 'self.ip' });

1;
