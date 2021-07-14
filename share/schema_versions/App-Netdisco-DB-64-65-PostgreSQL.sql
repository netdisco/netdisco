BEGIN;

UPDATE device SET name = dns WHERE vendor = 'netdisco';

COMMIT;
