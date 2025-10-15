BEGIN;

ALTER TABLE users ADD COLUMN portctl_checkpoint integer NOT NULL DEFAULT 0;

UPDATE users SET portctl_checkpoint = 1 WHERE portctl_role IS NOT NULL AND portctl_role != '';

COMMIT;
