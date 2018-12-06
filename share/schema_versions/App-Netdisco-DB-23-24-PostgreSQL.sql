BEGIN;

ALTER TABLE device_port ADD COLUMN "is_uplink" bool;
ALTER TABLE device_port ADD COLUMN "is_uplink_admin" bool;

COMMIT;
