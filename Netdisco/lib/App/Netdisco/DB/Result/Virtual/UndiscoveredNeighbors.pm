package App::Netdisco::DB::Result::Virtual::UndiscoveredNeighbors;

use strict;
use warnings;

use utf8;
use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('undiscovered_neighbors');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
    SELECT DISTINCT ON (p.remote_ip) d.ip,
                                     d.name,
                                     d.dns,
                                     p.port,
                                     p.remote_ip,
                                     p.remote_id,
                                     p.remote_type,
                                     p.remote_port,
                                     a.log,
                                     a.finished
    FROM device_port p
    JOIN device d ON d.ip = p.ip
    JOIN ADMIN a ON p.remote_ip = a.device
    WHERE p.remote_ip NOT IN
        (SELECT ALIAS
         FROM device_ip)
      AND a.action = 'discover'
    ORDER BY p.remote_ip,
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
  "remote_ip",
  { data_type => "inet", is_nullable => 1 },
  "remote_port",
  { data_type => "text", is_nullable => 1 },
  "remote_type",
  { data_type => "text", is_nullable => 1 },
  "remote_id",
  { data_type => "text", is_nullable => 1 },
  "log",
  { data_type => "text", is_nullable => 1 },
  "finished",
  { data_type => "timestamp", is_nullable => 1 },
);

1;
