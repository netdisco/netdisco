BEGIN;

UPDATE device SET name = dns WHERE vendor = 'netdisco' AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'device' AND column_name = 'is_pseudo');

COMMIT;
