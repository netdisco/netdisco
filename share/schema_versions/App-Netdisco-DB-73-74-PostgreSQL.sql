BEGIN;

ALTER TABLE snmp_object ADD COLUMN "status" text;
ALTER TABLE snmp_object ADD COLUMN "enum"   text[] DEFAULT '{}' NOT NULL;
ALTER TABLE snmp_object ADD COLUMN "descr"  text;

COMMIT;
