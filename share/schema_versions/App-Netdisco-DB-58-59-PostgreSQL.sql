BEGIN;

ALTER TABLE users ADD COLUMN "radius" boolean DEFAULT false;

UPDATE device SET layers = NULL WHERE vendor = 'netdisco';

UPDATE device SET layers = '00000000' WHERE layers IS NULL;

ALTER TABLE device ALTER layers SET DEFAULT '00000000';

COMMIT;
