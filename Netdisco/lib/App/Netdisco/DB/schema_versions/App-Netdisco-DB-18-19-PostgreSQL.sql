BEGIN;

ALTER TABLE device_port ADD COLUMN "manual_topo" bool DEFAULT false NOT NULL;

COMMIT;
