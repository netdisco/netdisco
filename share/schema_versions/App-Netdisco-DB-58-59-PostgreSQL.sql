BEGIN;

ALTER TABLE users ADD COLUMN "radius" boolean DEFAULT false;

UPDATE device SET layers = NULL WHERE vendor = 'netdisco';

COMMIT;
