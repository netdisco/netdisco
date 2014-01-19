BEGIN;

ALTER TABLE device_port DROP COLUMN is_uplink_admin;
ALTER TABLE device_port ADD COLUMN "slave_of"  text;
ALTER TABLE device_port ADD COLUMN "is_master" bool DEFAULT false NOT NULL;

COMMIT;
