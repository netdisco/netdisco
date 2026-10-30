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

-- device_ip_resolved maps each alias address to the one device that owns it.
-- An address in the default table (vrf = '') always resolves as recorded.
-- An address in a named VRF resolves when no device holds it in the default
-- table, and either it is the device's own address or no other device holds
-- it in any VRF. A device listing it in several VRFs gives one row.
-- With every vrf = '' the view returns device_ip's (ip, alias) pairs exactly.
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
        AND (x.vrf = ''
          OR (x.ip = row_ip AND x.vrf < row_vrf)
          OR (x.ip <> row_ip AND row_alias <> row_ip)))
  $$;

CREATE OR REPLACE VIEW device_ip_resolved AS
  SELECT d.ip, d.alias FROM device_ip d
    WHERE d.vrf = '' OR device_ip_vrf_row_resolves(d.ip, d.alias, d.vrf);

-- Lets alias lookups through the view stay index-only. idx_device_ip_alias
-- is left in place: the harness re-runs single steps and wants no catalog change.
CREATE INDEX IF NOT EXISTS idx_device_ip_alias_vrf_ip ON device_ip (alias, vrf, ip);

COMMIT;
