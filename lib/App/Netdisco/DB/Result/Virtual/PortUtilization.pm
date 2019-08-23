package App::Netdisco::DB::Result::Virtual::PortUtilization;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

# NOTE this query is in `git grep 'THREE PLACES'`
__PACKAGE__->table('port_utilization');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
 SELECT d.dns AS dns, d.ip as ip,
     sum(CASE WHEN (dp.type != 'propVirtual') THEN 1
              ELSE 0 END) as port_count,
     sum(CASE WHEN (dp.type != 'propVirtual' AND dp.up_admin = 'up' AND dp.up = 'up') THEN 1
              ELSE 0 END) as ports_in_use,
     sum(CASE WHEN (dp.type != 'propVirtual' AND dp.up_admin != 'up') THEN 1
              ELSE 0 END) as ports_shutdown,
     sum(CASE
      WHEN ( dp.type != 'propVirtual' AND dp.up_admin = 'up' AND dp.up != 'up'
             AND (age(now(), to_timestamp(extract(epoch from d.last_discover) - (d.uptime/100))) < ?::interval)
             AND (last_node.time_last IS NULL OR (age(now(), last_node.time_last)) > ?::interval) )
        THEN 1
      WHEN ( dp.type != 'propVirtual' AND dp.up_admin = 'up' AND dp.up != 'up'
             AND (age(now(), to_timestamp(extract(epoch from d.last_discover) - (d.uptime - dp.lastchange)/100)) > ?::interval) )
        THEN 1
      ELSE 0
     END) as ports_free
   FROM device d
   LEFT JOIN device_port dp
     ON d.ip = dp.ip
   LEFT JOIN
     ( SELECT DISTINCT ON (switch, port) * FROM node
         ORDER BY switch, port, time_last desc ) AS last_node
     ON dp.port = last_node.port AND dp.ip = last_node.switch
   GROUP BY d.dns, d.ip
   ORDER BY d.dns, d.ip
ENDSQL
);

__PACKAGE__->add_columns(
  'dns' => {
    data_type => 'text',
  },
  'ip' => {
    data_type => 'inet',
  },
  'port_count' => {
    data_type => 'integer',
  },
  'ports_in_use' => {
    data_type => 'integer',
  },
  'ports_shutdown' => {
    data_type => 'integer',
  },
  'ports_free' => {
    data_type => 'integer',
  },
);

1;
