package App::Netdisco::DB::Result::Virtual::CidrIps;

use strict;
use warnings;

use utf8;
use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('cidr_ips');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
SELECT host(network (cidr) + sub.int)::inet AS ip, NULL::text AS dns,
  NULL::timestamp AS time_first, NULL::timestamp AS time_last, false::boolean AS active
FROM
  ( SELECT cidr, generate_series(1, broadcast(cidr) - (network(cidr)) - 1) AS int
FROM (
SELECT CASE WHEN family(cidr) = 4 THEN cidr
       ELSE '0.0.0.0/32'::inet
       END AS cidr
FROM ( SELECT ?::inet AS cidr) AS input) AS addr
) AS sub
ENDSQL

__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "dns",
  { data_type => "text", is_nullable => 1 },
  "active",
  { data_type => "boolean", is_nullable => 1 },
  "time_first",
  {
    data_type     => "timestamp",
    is_nullable   => 1,
  },
  "time_last",
  {
    data_type     => "timestamp",
    is_nullable   => 1,
  },
);

1;