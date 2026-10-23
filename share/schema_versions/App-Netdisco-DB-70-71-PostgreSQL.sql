BEGIN;

ALTER TABLE device_port_properties ADD COLUMN "remote_is_discoverable" bool DEFAULT true;

COMMIT;
