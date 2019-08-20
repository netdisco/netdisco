BEGIN;

UPDATE device SET layers = '00000100' WHERE vendor = 'netdisco';

COMMIT;
