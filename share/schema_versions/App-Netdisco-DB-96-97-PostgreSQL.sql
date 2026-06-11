BEGIN;

ALTER TABLE users ADD COLUMN token_no_expire boolean DEFAULT false;
ALTER TABLE users ADD COLUMN token_allowed_ips text[];
ALTER TABLE users ADD COLUMN token_auth_only boolean DEFAULT false;

COMMIT;
