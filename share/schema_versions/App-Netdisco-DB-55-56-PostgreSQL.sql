BEGIN;

UPDATE device SET layers = '00000100' WHERE vendor = 'netdisco' AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'device' AND column_name = 'is_pseudo');

COMMIT;
