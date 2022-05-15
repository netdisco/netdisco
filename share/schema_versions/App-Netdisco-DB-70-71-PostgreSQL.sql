BEGIN;

ALTER TABLE device_port_properties ADD COLUMN "remote_is_discoverable" bool DEFAULT true;

UPDATE device_port_properties SET remote_is_discoverable = true;

COMMIT;
