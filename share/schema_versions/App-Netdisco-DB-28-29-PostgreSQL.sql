BEGIN;

ALTER TABLE device DROP COLUMN snmp_comm_rw;

COMMIT;
