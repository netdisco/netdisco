BEGIN;

ALTER TABLE users ADD radius boolean;

ALTER TABLE users ALTER radius SET DEFAULT false;

COMMIT;
