package App::Netdisco::DB::Result::Virtual::UndiscoveredNeighbors;

use strict;
use warnings;

use utf8;
use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('undiscovered_neighbors');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
  SELECT DISTINCT ON (p.remote_ip, p.port)
    d.ip, d.name, d.dns,
    p.port, p.name AS port_description,
    p.remote_ip, p.remote_id, p.remote_type, p.remote_port,
    l.log AS comment,
    a.log, a.finished

  FROM device_port p

  INNER JOIN device d USING (ip)
  LEFT OUTER JOIN device_skip ds
    ON ('discover' = ANY(ds.actionset) AND p.remote_ip = ds.device)
  LEFT OUTER JOIN device_port_log l USING (ip, port)
  LEFT OUTER JOIN admin a
    ON (p.remote_ip = a.device AND a.action = 'discover')

  WHERE
    ds.device IS NULL
    AND ((p.remote_ip NOT IN (SELECT alias FROM device_ip))
         OR ((p.remote_ip IS NULL) AND p.is_uplink))

  ORDER BY
    p.remote_ip ASC,
    p.port ASC,
    l.creation DESC,
    a.finished DESC
ENDSQL

__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "name",
  { data_type => "text", is_nullable => 1 },
  "dns",
  { data_type => "text", is_nullable => 1 },
  "port",
  { data_type => "text", is_nullable => 0 },
  "port_description",
  { data_type => "text", is_nullable => 0 },
  "remote_ip",
  { data_type => "inet", is_nullable => 1 },
  "remote_port",
  { data_type => "text", is_nullable => 1 },
  "remote_type",
  { data_type => "text", is_nullable => 1 },
  "remote_id",
  { data_type => "text", is_nullable => 1 },
  "comment",
  { data_type => "text", is_nullable => 1 },
  "log",
  { data_type => "text", is_nullable => 1 },
  "finished",
  { data_type => "timestamp", is_nullable => 1 },
);

1;
