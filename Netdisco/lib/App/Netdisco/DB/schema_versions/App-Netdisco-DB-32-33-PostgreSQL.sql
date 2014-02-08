BEGIN;

ALTER TABLE community ADD COLUMN snmp_auth_tag text;

COMMIT;
