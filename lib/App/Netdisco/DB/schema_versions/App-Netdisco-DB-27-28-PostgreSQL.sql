BEGIN;

ALTER TABLE device ADD COLUMN snmp_comm_rw text;

COMMIT;
