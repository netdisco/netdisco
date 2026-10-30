BEGIN;

SET LOCAL client_min_messages = warning;

-- Adds a vrf key to device_ip and subnets. The default table is vrf = ''
-- and never NULL, so that upserts can name the key. The column is added bare
-- because on 9.6 a default in ADD COLUMN rewrites the table.
ALTER TABLE device_ip ADD COLUMN IF NOT EXISTS vrf text;
ALTER TABLE device_ip ALTER COLUMN vrf SET DEFAULT '';
UPDATE device_ip SET vrf = '' WHERE vrf IS NULL;
ALTER TABLE device_ip ALTER COLUMN vrf SET NOT NULL;
ALTER TABLE device_ip DROP CONSTRAINT IF EXISTS device_ip_pkey;
ALTER TABLE device_ip ADD CONSTRAINT device_ip_pkey PRIMARY KEY (ip, alias, vrf);

ALTER TABLE subnets ADD COLUMN IF NOT EXISTS vrf text;
ALTER TABLE subnets ALTER COLUMN vrf SET DEFAULT '';
UPDATE subnets SET vrf = '' WHERE vrf IS NULL;
ALTER TABLE subnets ALTER COLUMN vrf SET NOT NULL;
ALTER TABLE subnets DROP CONSTRAINT IF EXISTS subnets_pkey;
ALTER TABLE subnets ADD CONSTRAINT subnets_pkey PRIMARY KEY (net, vrf);

-- device_ip_resolved maps each alias address to the one device that owns it.
-- An address in the default table (vrf = '') always resolves as recorded.
-- An address in a named VRF resolves when it is the device's own address,
-- or when no default-table device holds it and exactly one device does.
-- With every vrf = '' the view returns device_ip's (ip, alias) pairs exactly.
CREATE OR REPLACE VIEW device_ip_resolved AS
  SELECT ip, alias FROM device_ip WHERE vrf = ''
  UNION
  SELECT ip, alias FROM device_ip WHERE vrf <> '' AND alias = ip
  UNION
  SELECT (array_agg(d.ip))[1] AS ip, d.alias FROM device_ip d
    WHERE d.vrf <> ''
      AND NOT EXISTS (SELECT 1 FROM device_ip x WHERE x.alias = d.alias AND x.vrf = '')
    GROUP BY d.alias
    HAVING count(DISTINCT d.ip) = 1;

COMMIT;
