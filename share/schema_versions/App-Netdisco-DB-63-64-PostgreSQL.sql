BEGIN;

ALTER TABLE netmap_positions DROP CONSTRAINT netmap_positions_device_groups_key;

COMMIT;
