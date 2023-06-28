BEGIN;

ALTER TABLE users ADD COLUMN "portctl_role" text;

COMMIT;
