BEGIN;

ALTER TABLE device_port_properties ADD COLUMN "speed_admin" text;

COMMIT;
