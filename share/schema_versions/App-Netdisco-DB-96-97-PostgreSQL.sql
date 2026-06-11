BEGIN;

ALTER TABLE users ADD COLUMN token_no_expire boolean DEFAULT false;
ALTER TABLE users ADD COLUMN token_allowed_ips text[];

COMMIT;
