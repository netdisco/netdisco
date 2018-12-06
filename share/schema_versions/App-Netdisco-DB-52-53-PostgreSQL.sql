BEGIN;

ALTER TABLE netmap_positions DROP CONSTRAINT "netmap_positions_device_groups_vlan_key";

ALTER TABLE netmap_positions RENAME COLUMN device_groups TO host_groups;

ALTER TABLE netmap_positions ALTER COLUMN host_groups SET DEFAULT '{}';

ALTER TABLE netmap_positions ADD COLUMN "device" inet;

ALTER TABLE netmap_positions ADD COLUMN "locations" text[] DEFAULT '{}' NOT NULL;

COMMIT;
