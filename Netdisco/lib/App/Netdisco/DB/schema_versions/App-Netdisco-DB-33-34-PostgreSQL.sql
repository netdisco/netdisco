BEGIN;

UPDATE node SET vlan = '0' WHERE vlan IS NULL;

COMMIT;
