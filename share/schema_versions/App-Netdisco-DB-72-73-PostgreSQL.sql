BEGIN;

ALTER TABLE snmp_object ADD COLUMN "num_children" integer DEFAULT 0 NOT NULL;

COMMIT;
