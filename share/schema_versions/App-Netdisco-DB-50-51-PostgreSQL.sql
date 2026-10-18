BEGIN;

ALTER TABLE netmap_positions DROP CONSTRAINT IF EXISTS "netmap_positions_device_groups_vlan_key";

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'netmap_positions' AND column_name = 'device_groups') THEN
    ALTER TABLE netmap_positions RENAME COLUMN device_groups TO host_groups;
  END IF;
END
$$;

ALTER TABLE netmap_positions ALTER COLUMN host_groups SET DEFAULT '{}';

ALTER TABLE netmap_positions ADD COLUMN IF NOT EXISTS "device" inet;

ALTER TABLE netmap_positions ADD COLUMN IF NOT EXISTS "locations" text[] DEFAULT '{}' NOT NULL;

COMMIT;
