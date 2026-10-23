BEGIN;

ALTER TABLE users ADD COLUMN "radius" boolean DEFAULT false;

UPDATE device SET layers = NULL WHERE vendor = 'netdisco' AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'device' AND column_name = 'is_pseudo');

UPDATE device SET layers = '00000000' WHERE layers IS NULL;

ALTER TABLE device ALTER layers SET DEFAULT '00000000';

COMMIT;
