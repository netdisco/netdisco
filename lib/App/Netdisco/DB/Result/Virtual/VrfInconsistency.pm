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
       'domain holds ' || array_to_string(array_agg(DISTINCT m.vrf ORDER BY m.vrf), ', ') AS detail,
       ARRAY[d.id] AS domain_ids,
       (SELECT string_agg(x.name || ' (#' || x.id || ')', ', ' ORDER BY x.id) FROM l3_domain x WHERE x.id = ANY(ARRAY[d.id])) AS domains
  FROM l3_domain_member m
  JOIN l3_domain d ON d.id = m.domain_id
 WHERE m.vrf <> ''
   -- vrf_domains groups different names on purpose
   AND (d.inferred_name IS NULL OR d.inferred_name NOT LIKE 'manual:%')
 GROUP BY d.id, d.name
HAVING count(DISTINCT m.vrf) > 1
UNION ALL
-- same name once case and punctuation are ignored, but kept in separate domains
SELECT 'similar names' AS finding,
       (array_agg(d.name ORDER BY m.vrf, m.domain_id))[1] AS domain,
       array_agg(DISTINCT m.vrf ORDER BY m.vrf) AS vrfs,
       count(DISTINCT m.ip)::integer AS devices,
       'case or punctuation' AS detail,
       array_agg(DISTINCT m.domain_id ORDER BY m.domain_id) AS domain_ids,
       (SELECT string_agg(x.name || ' (#' || x.id || ')', ', ' ORDER BY x.id) FROM l3_domain x WHERE x.id = ANY(array_agg(DISTINCT m.domain_id ORDER BY m.domain_id))) AS domains
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
       'RD ' || v.rd AS detail,
       array_agg(DISTINCT m.domain_id ORDER BY m.domain_id) AS domain_ids,
       (SELECT string_agg(x.name || ' (#' || x.id || ')', ', ' ORDER BY x.id) FROM l3_domain x WHERE x.id = ANY(array_agg(DISTINCT m.domain_id ORDER BY m.domain_id))) AS domains
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
       'subnet ' || p.subnet || ' between ' || host(p.lo_ip) || ' and ' || host(p.hi_ip) AS detail,
       NULLIF(array_remove(ARRAY[p.lo_domain, p.hi_domain], NULL), '{}') AS domain_ids,
       (SELECT string_agg(x.name || ' (#' || x.id || ')', ', ' ORDER BY x.id) FROM l3_domain x WHERE x.id = ANY(NULLIF(array_remove(ARRAY[p.lo_domain, p.hi_domain], NULL), '{}'))) AS domains
  FROM (
    SELECT DISTINCT
           CASE WHEN l.a_ip < l.b_ip THEN l.a_ip ELSE l.b_ip END AS lo_ip,
           CASE WHEN l.a_ip < l.b_ip THEN l.a_vrf ELSE l.b_vrf END AS lo_vrf,
           CASE WHEN l.a_ip < l.b_ip THEN l.a_domain ELSE l.b_domain END AS lo_domain,
           CASE WHEN l.a_ip < l.b_ip THEN l.b_ip ELSE l.a_ip END AS hi_ip,
           CASE WHEN l.a_ip < l.b_ip THEN l.b_vrf ELSE l.a_vrf END AS hi_vrf,
           CASE WHEN l.a_ip < l.b_ip THEN l.b_domain ELSE l.a_domain END AS hi_domain,
           l.subnet
      FROM (
        SELECT pr.a_ip, ia.vrf AS a_vrf, ma.domain_id AS a_domain,
               pr.b_ip, ib.vrf AS b_vrf, mb.domain_id AS b_domain,
               ia.subnet AS subnet
          FROM (
            SELECT DISTINCT dp.ip AS a_ip, dp.port AS a_port, r.ip AS b_ip
              FROM device_port dp
              JOIN device_ip_resolved r ON r.alias = dp.remote_ip
             WHERE dp.ip <> r.ip
          ) pr
          -- the subnet must be on the neighbor's port (or a subinterface of
          -- it): equal private space elsewhere on two neighbors is reuse
          JOIN device_ip ia ON ia.ip = pr.a_ip AND ia.vrf <> '' AND ia.subnet IS NOT NULL
               AND (ia.port = pr.a_port OR left(ia.port, length(pr.a_port) + 1) = pr.a_port || '.')
          JOIN device_ip ib ON ib.ip = pr.b_ip AND ib.vrf <> '' AND ib.subnet = ia.subnet AND ia.alias <> ib.alias
          LEFT JOIN l3_domain_member ma ON ma.ip = ia.ip AND ma.vrf = ia.vrf
          LEFT JOIN l3_domain_member mb ON mb.ip = ib.ip AND mb.vrf = ib.vrf
         WHERE ma.domain_id IS DISTINCT FROM mb.domain_id
           -- a subnet a device holds in two named VRFs is reused space, so
           -- which VRF faces the neighbor is unknown: pair only single holders
           AND NOT EXISTS (SELECT 1 FROM device_ip xa WHERE xa.ip = ia.ip AND xa.subnet = ia.subnet
                 AND xa.vrf <> '' AND xa.vrf <> ia.vrf)
           AND NOT EXISTS (SELECT 1 FROM device_ip xb WHERE xb.ip = ib.ip AND xb.subnet = ib.subnet
                 AND xb.vrf <> '' AND xb.vrf <> ib.vrf)
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
  "domain_ids",
  { data_type => "integer[]", is_nullable => 1 },
  "domains",
  { data_type => "text", is_nullable => 1 },
);

1;
