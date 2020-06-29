BEGIN;

ALTER TABLE device ADD snmp_engineid text;

COMMIT;
