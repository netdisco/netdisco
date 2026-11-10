package App::Netdisco::DB::Result::Virtual::CidrIpsByDomain;

use strict;
use warnings;

use utf8;
use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('cidr_ips_by_domain');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
WITH addr AS (
  SELECT ?::inet AS prefix
),
-- one row per stored subnet overlapping the prefix, as the host offsets it
-- covers there, so l3_domain_of runs per subnet, not per generated address;
-- DISTINCT only folds subnets clamped to the same range and domain.
-- LEAST compares offsets: inets of two lengths order by masked network first
cand AS (
  SELECT DISTINCT
         GREATEST(network(s.net) - network(a.prefix), 1) AS lo,
         LEAST(broadcast(s.net) - network(a.prefix), broadcast(a.prefix) - network(a.prefix) - 1) AS hi,
         CASE WHEN s.vrf = '' THEN 0 ELSE l3_domain_of(s.router_last, s.vrf) END AS domain
    FROM subnets s, addr a
   WHERE s.net && a.prefix
),
-- a NULL (ambiguous) domain holds nothing, so it adds no domain 0 row
held AS (
  SELECT DISTINCT generate_series(lo, hi) AS int, domain
    FROM cand
   WHERE domain IS NOT NULL
)
SELECT host(network(a.prefix) + o.int)::inet AS ip,
       NULL::macaddr AS mac,
       NULL::timestamp AS time_first,
       NULL::timestamp AS time_last,
       NULL::text AS dns,
       false::boolean AS active,
       false::boolean AS node,
       replace( date_trunc( 'minute', age( LOCALTIMESTAMP, NULL::timestamp ) ) ::text, 'mon', 'month') AS age,
       NULL::text AS vendor,
       NULL::text AS nbname,
       o.domain
  FROM addr a, (
    SELECT int, domain FROM held
    UNION ALL
    SELECT g.int, 0 FROM addr, generate_series(1, (broadcast(prefix) - network(prefix) - 1)) AS g(int)
     WHERE NOT EXISTS (SELECT 1 FROM held h WHERE h.int = g.int)
  ) AS o
ENDSQL

__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "mac",
  { data_type => "macaddr", is_nullable => 1 },
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
  "dns",
  { data_type => "text", is_nullable => 1 },
  "active",
  { data_type => "boolean", is_nullable => 1 },
  "node",
  { data_type => "boolean", is_nullable => 1 },
  "age",
  { data_type => "text", is_nullable => 1 },
  "vendor",
  { data_type => "text", is_nullable => 1 },
  "nbname",
  { data_type => "text", is_nullable => 1 },
  "domain",
  { data_type => "integer", is_nullable => 0 },
);

1;
