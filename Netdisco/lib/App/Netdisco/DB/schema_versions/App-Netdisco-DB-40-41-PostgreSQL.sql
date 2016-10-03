BEGIN;

ALTER TABLE community RENAME COLUMN snmp_auth_tag TO snmp_auth_tag_read;

ALTER TABLE community ADD COLUMN snmp_auth_tag_write text;

COMMIT;
