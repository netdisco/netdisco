BEGIN;

ALTER TABLE device ADD COLUMN "tags" text[] DEFAULT '{}' NOT NULL;

ALTER TABLE device_port ADD COLUMN "tags" text[] DEFAULT '{}' NOT NULL;

COMMIT;
