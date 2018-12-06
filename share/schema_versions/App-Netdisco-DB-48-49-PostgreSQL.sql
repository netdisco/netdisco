BEGIN;

ALTER TABLE device_port_properties ADD COLUMN "raw_speed" bigint DEFAULT 0;

COMMIT;
