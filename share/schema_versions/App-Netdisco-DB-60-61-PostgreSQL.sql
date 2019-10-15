BEGIN;

ALTER TABLE users ADD COLUMN "tacacs" boolean DEFAULT false;

COMMIT;
