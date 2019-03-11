BEGIN;

ALTER TABLE users ADD COLUMN "token" text;

ALTER TABLE users ADD COLUMN "token_from" integer;

COMMIT;
