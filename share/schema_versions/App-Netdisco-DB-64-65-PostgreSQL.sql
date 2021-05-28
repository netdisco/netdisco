BEGIN;

UPDATE device SET model = 'pseudodevice' WHERE vendor = 'netdisco';

UPDATE device SET name = dns WHERE vendor = 'netdisco' AND name IS NULL;

UPDATE device SET os_ver = '2.47.6' WHERE vendor = 'netdisco' AND os_ver IS NULL;

UPDATE device SET os = 'netdisco' WHERE vendor = 'netdisco' AND os IS NULL;

COMMIT;
