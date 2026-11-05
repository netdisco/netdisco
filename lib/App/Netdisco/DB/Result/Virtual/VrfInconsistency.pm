package App::Netdisco::DB::Result::Virtual::VrfInconsistency;

use strict;
use warnings;

use utf8;
use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('vrf_inconsistency');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
SELECT 'different names' AS finding,
       d.name AS domain,
       array_agg(DISTINCT m.vrf ORDER BY m.vrf) AS vrfs,
       count(DISTINCT m.ip)::integer AS devices,
       'domain holds ' || array_to_string(array_agg(DISTINCT m.vrf ORDER BY m.vrf), ', ') AS detail
  FROM l3_domain_member m
  JOIN l3_domain d ON d.id = m.domain_id
 WHERE m.vrf <> ''
 GROUP BY d.id, d.name
HAVING count(DISTINCT m.vrf) > 1
UNION ALL
-- same name once case and punctuation are ignored, but kept in separate domains
SELECT 'similar names' AS finding,
       (array_agg(d.name ORDER BY m.vrf, m.domain_id))[1] AS domain,
       array_agg(DISTINCT m.vrf ORDER BY m.vrf) AS vrfs,
       count(DISTINCT m.ip)::integer AS devices,
       'case or punctuation' AS detail
  FROM l3_domain_member m
  JOIN l3_domain d ON d.id = m.domain_id
 WHERE m.vrf <> ''
   AND lower(regexp_replace(m.vrf, '[^A-Za-z0-9]', '', 'g')) <> ''
 GROUP BY lower(regexp_replace(m.vrf, '[^A-Za-z0-9]', '', 'g'))
HAVING count(DISTINCT m.domain_id) > 1
   AND count(DISTINCT m.vrf) > 1
UNION ALL
-- an RD is a hint only: nothing joins on it
SELECT 'shared RD' AS finding,
       (array_agg(d.name ORDER BY v.vrf, m.domain_id))[1] AS domain,
       array_agg(DISTINCT v.vrf ORDER BY v.vrf) AS vrfs,
       count(DISTINCT v.ip)::integer AS devices,
       'RD ' || v.rd AS detail
  FROM device_vrf v
  JOIN l3_domain_member m ON m.ip = v.ip AND m.vrf = v.vrf
  JOIN l3_domain d ON d.id = m.domain_id
 WHERE v.vrf <> '' AND v.rd IS NOT NULL
 GROUP BY v.rd
HAVING count(DISTINCT m.domain_id) > 1
UNION ALL
-- a missing member row on one side only counts as a different domain
SELECT 'linked, one subnet' AS finding,
       COALESCE(d.name, '') AS domain,
       ARRAY[p.lo_vrf, p.hi_vrf] AS vrfs,
       2 AS devices,
       'subnet ' || p.subnet || ' between ' || host(p.lo_ip) || ' and ' || host(p.hi_ip) AS detail
  FROM (
    SELECT DISTINCT
           CASE WHEN l.a_ip < l.b_ip THEN l.a_ip ELSE l.b_ip END AS lo_ip,
           CASE WHEN l.a_ip < l.b_ip THEN l.a_vrf ELSE l.b_vrf END AS lo_vrf,
           CASE WHEN l.a_ip < l.b_ip THEN l.a_domain ELSE l.b_domain END AS lo_domain,
           CASE WHEN l.a_ip < l.b_ip THEN l.b_ip ELSE l.a_ip END AS hi_ip,
           CASE WHEN l.a_ip < l.b_ip THEN l.b_vrf ELSE l.a_vrf END AS hi_vrf,
           l.subnet
      FROM (
        SELECT pr.a_ip, ia.vrf AS a_vrf, ma.domain_id AS a_domain,
               pr.b_ip, ib.vrf AS b_vrf, mb.domain_id AS b_domain,
               ia.subnet AS subnet
          FROM (
            SELECT DISTINCT dp.ip AS a_ip, r.ip AS b_ip
              FROM device_port dp
              JOIN device_ip_resolved r ON r.alias = dp.remote_ip
             WHERE dp.ip <> r.ip
          ) pr
          JOIN device_ip ia ON ia.ip = pr.a_ip AND ia.vrf <> '' AND ia.subnet IS NOT NULL
          JOIN device_ip ib ON ib.ip = pr.b_ip AND ib.vrf <> '' AND ib.subnet = ia.subnet
          LEFT JOIN l3_domain_member ma ON ma.ip = ia.ip AND ma.vrf = ia.vrf
          LEFT JOIN l3_domain_member mb ON mb.ip = ib.ip AND mb.vrf = ib.vrf
         WHERE ma.domain_id IS DISTINCT FROM mb.domain_id
      ) l
  ) p
  LEFT JOIN l3_domain d ON d.id = p.lo_domain
ENDSQL

__PACKAGE__->add_columns(
  "finding",
  { data_type => "text", is_nullable => 0 },
  "domain",
  { data_type => "text", is_nullable => 1 },
  "vrfs",
  { data_type => "text[]", is_nullable => 0 },
  "devices",
  { data_type => "integer", is_nullable => 0 },
  "detail",
  { data_type => "text", is_nullable => 0 },
);

1;
