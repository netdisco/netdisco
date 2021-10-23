BEGIN;

ALTER TABLE device ADD COLUMN "is_pseudo" boolean DEFAULT false;

UPDATE device SET is_pseudo = false;

UPDATE device SET is_pseudo = true WHERE vendor = 'netdisco';

COMMIT;
