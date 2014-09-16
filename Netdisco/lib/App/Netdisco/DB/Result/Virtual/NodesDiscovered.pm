package App::Netdisco::DB::Result::Virtual::NodesDiscovered;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('nodes_discovered');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
SELECT d.ip,
       d.dns,
       d.name,
       p.port,
       p.remote_ip,
       p.remote_port,
       p.remote_type,
       p.remote_id
FROM device_port p,
     device d
WHERE d.ip = p.ip
  AND NOT EXISTS
    (SELECT 1
     FROM device_port q
     WHERE q.ip = p.remote_ip
       AND q.port = p.remote_port)
  AND NOT EXISTS
    (SELECT 1
     FROM device_ip a,
          device_port q
     WHERE a.alias = p.remote_ip
       AND q.ip = a.ip
       AND q.port = p.remote_port)
  AND (p.remote_id IS NOT NULL OR p.remote_type IS NOT NULL)
ENDSQL
);

__PACKAGE__->add_columns(
  'ip' => {
    data_type => 'inet',
  },
  'dns' => {
    data_type => 'text',
  },
  'name' => {
    data_type => 'text',
  },
  'port' => {
    data_type => 'text',
  },
  'remote_ip' => {
    data_type => 'inet',
  },
  'remote_port' => {
    data_type => 'text',
  },
  'remote_type' => {
    data_type => 'text',
  },
  'remote_id' => {
    data_type => 'text',
  },
);

1;
