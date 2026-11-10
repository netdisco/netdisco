BEGIN;

SET LOCAL client_min_messages = warning;

-- Adds a vrf key to device_ip and subnets. The default table is vrf = ''
-- and never NULL, so that upserts can name the key.
ALTER TABLE device_ip ADD COLUMN IF NOT EXISTS vrf text NOT NULL DEFAULT '';
ALTER TABLE device_ip DROP CONSTRAINT IF EXISTS device_ip_pkey;
ALTER TABLE device_ip ADD CONSTRAINT device_ip_pkey PRIMARY KEY (ip, alias, vrf);

ALTER TABLE subnets ADD COLUMN IF NOT EXISTS vrf text NOT NULL DEFAULT '';
ALTER TABLE subnets DROP CONSTRAINT IF EXISTS subnets_pkey;
ALTER TABLE subnets ADD CONSTRAINT subnets_pkey PRIMARY KEY (net, vrf);

-- device_ip_resolved maps each alias address to the device that owns it.
-- An address in the default table (vrf = '') always resolves as recorded.
-- A device's own address (alias = ip) in a named VRF always resolves, so
-- another device listing it in the default table cannot hide the device
-- polled on it: both rows resolve, as two default-table rows would.
-- Any other address in a named VRF resolves when no device holds it in the
-- default table and no other device holds it in any VRF.
-- A device listing an address in several VRFs gives one row.
-- With every vrf = '' the view returns device_ip's (ip, alias) pairs exactly.
-- The row kept is the pair's lowest VRF, the row ORDER BY vrf LIMIT 1 would
-- pick, so its dns matches that lookup.
--
-- One scan of device_ip keeps its statistics and lets alias = ? reach its
-- indexes. A UNION ALL view loses the statistics and inline NOT EXISTS is
-- costed on every row; both pushed the view's consumers into JIT. The
-- named-VRF test is a function the OR calls only for vrf <> '' rows.
-- COST 1 and PARALLEL SAFE are deliberate planner hints: keep them.
CREATE OR REPLACE FUNCTION device_ip_vrf_row_resolves(row_ip inet, row_alias inet, row_vrf text)
  RETURNS boolean LANGUAGE sql STABLE PARALLEL SAFE COST 1 AS $$
    SELECT NOT EXISTS (SELECT 1 FROM device_ip x
      WHERE x.alias = row_alias
        AND ((x.vrf = '' AND row_alias <> row_ip)
          OR (x.ip = row_ip AND x.vrf < row_vrf)
          OR (x.ip <> row_ip AND row_alias <> row_ip)))
  $$;

CREATE OR REPLACE VIEW device_ip_resolved AS
  SELECT d.ip, d.alias, d.dns FROM device_ip d
    WHERE d.vrf = '' OR device_ip_vrf_row_resolves(d.ip, d.alias, d.vrf);

-- Lets alias lookups through the view stay index-only. idx_device_ip_alias
-- is left in place: the harness re-runs single steps and wants no catalog change.
CREATE INDEX IF NOT EXISTS idx_device_ip_alias_vrf_ip ON device_ip (alias, vrf, ip);

-- VRF instances and L3 domains.
--
-- device_vrf holds every instance a device reports, the default table
-- included as vrf = ''. rd NULL means unset. l3_domain_member places a
-- (device, vrf) pair in a domain, inferred or set by hand. A row with
-- vrf = '' is domain 0 and has no member rows.
--
-- l3_domain_of(router, vrf) gives the domain of an address row: '' is 0;
-- else the domain of the member (router, vrf); else, when exactly one
-- domain has members named vrf, that one; else NULL, so that a reader
-- leaves an ambiguous row out of every domain total rather than guessing.
-- A NULL router skips to the name step.
-- Inference keys domains by inferred_name; name is for display.
CREATE TABLE IF NOT EXISTS device_vrf (
  ip inet NOT NULL,
  vrf text NOT NULL,
  kind text,
  rd text,
  rt_import text[] NOT NULL DEFAULT '{}',
  rt_export text[] NOT NULL DEFAULT '{}',
  l3_isid integer,
  listed_by text,
  complete boolean NOT NULL DEFAULT false,
  last_discover timestamp,
  PRIMARY KEY (ip, vrf)
);

CREATE TABLE IF NOT EXISTS l3_domain (
  id serial PRIMARY KEY,
  name text NOT NULL,
  inferred_name text
);

-- A table made by an earlier version of this step lacks the column.
ALTER TABLE l3_domain ADD COLUMN IF NOT EXISTS inferred_name text;

CREATE UNIQUE INDEX IF NOT EXISTS l3_domain_inferred_name_key ON l3_domain (inferred_name);

INSERT INTO l3_domain (id, name) VALUES (0, '') ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS l3_domain_member (
  ip inet NOT NULL,
  vrf text NOT NULL,
  domain_id integer NOT NULL,
  reason text NOT NULL,
  source text NOT NULL CHECK (source IN ('inferred', 'manual')),
  PRIMARY KEY (ip, vrf)
);

CREATE INDEX IF NOT EXISTS idx_l3_domain_member_vrf ON l3_domain_member (vrf, domain_id);

-- Added bare: catalog-only on 9.6, and no backfill, because every row is
-- vrf = '' (domain 0) whatever its router until the switch is on.
ALTER TABLE node_ip ADD COLUMN IF NOT EXISTS router_last inet;
ALTER TABLE subnets ADD COLUMN IF NOT EXISTS router_last inet;

-- Serves arpnip's retirement of named-VRF rows. It references only vrf, a key
-- column never updated, and active, already indexed, so router_last flips stay
-- HOT; it is empty until a site turns store_vrfs on.
CREATE INDEX IF NOT EXISTS idx_node_ip_vrf_named_active ON node_ip (vrf) WHERE active AND vrf <> '';

-- Default COST on purpose: COST 1 measured no faster (device_ip_vrf_row_resolves keeps its COST 1).
CREATE OR REPLACE FUNCTION l3_domain_of(row_router inet, row_vrf text)
  RETURNS integer LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT CASE WHEN row_vrf = '' THEN 0
      ELSE COALESCE(
        (SELECT m.domain_id FROM l3_domain_member m
          WHERE m.ip = row_router AND m.vrf = row_vrf),
        (SELECT (array_agg(DISTINCT n.domain_id))[1] FROM l3_domain_member n
          WHERE n.vrf = row_vrf HAVING count(DISTINCT n.domain_id) = 1))
      END
  $$;

COMMIT;
