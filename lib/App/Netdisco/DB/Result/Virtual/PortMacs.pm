use utf8;
package App::Netdisco::DB::Result::Virtual::PortMacs;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table("port_macs");
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
  SELECT all.ip, all.mac

  FROM
    (SELECT ip, mac FROM device
      UNION
    SELECT ip, mac FROM device_port) all

  INNER JOIN
    (SELECT unnest( ? )) locals(m)
    ON (all.mac = locals.m ::macaddr)

ENDSQL
);

__PACKAGE__->add_columns(
  'mac' => { data_type => 'macaddr' },
  'ip'  => { data_type => 'inet' },
);

1;
