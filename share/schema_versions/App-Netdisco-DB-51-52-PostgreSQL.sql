BEGIN;

ALTER TABLE device_port_properties ADD COLUMN "faststart" bool DEFAULT false;

COMMIT;
