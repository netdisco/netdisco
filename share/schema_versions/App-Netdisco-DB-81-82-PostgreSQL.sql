BEGIN;

ALTER TABLE admin ADD COLUMN "backend" text;

COMMIT;
