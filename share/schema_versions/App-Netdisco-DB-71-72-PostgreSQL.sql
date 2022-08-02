BEGIN;

ALTER TABLE device_port ADD COLUMN "has_subinterfaces" bool DEFAULT false NOT NULL;

COMMIT;
