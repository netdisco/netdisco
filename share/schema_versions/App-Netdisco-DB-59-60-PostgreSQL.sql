BEGIN;

ALTER TABLE device_port ADD COLUMN "speed_admin" text;

COMMIT;
