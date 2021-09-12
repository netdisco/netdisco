BEGIN;

UPDATE device SET model = 'pseudodevice' WHERE vendor = 'netdisco';

UPDATE device SET os_ver = '2.49.5' WHERE vendor = 'netdisco' AND os_ver IS NULL;

UPDATE device SET os = 'netdisco' WHERE vendor = 'netdisco' AND os IS NULL;

COMMIT;
