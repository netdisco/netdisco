BEGIN;

ALTER TABLE device_port_properties ADD COLUMN "remote_dns" text;

COMMIT;
