BEGIN;

ALTER TABLE users ADD COLUMN token_no_expire boolean DEFAULT false;

COMMIT;
