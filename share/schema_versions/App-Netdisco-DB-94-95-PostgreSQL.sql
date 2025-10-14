BEGIN;

ALTER TABLE users ADD COLUMN portctl_checkpoint integer NOT NULL DEFAULT 0;

COMMIT;
