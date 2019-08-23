BEGIN;

ALTER TABLE users ADD COLUMN "radius" boolean DEFAULT false;

COMMIT;
