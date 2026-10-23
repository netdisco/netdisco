BEGIN;

ALTER TABLE netmap_positions DROP CONSTRAINT IF EXISTS netmap_positions_device_groups_key;

COMMIT;
