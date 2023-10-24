BEGIN;

UPDATE admin SET backend = regexp_replace(status, '^queued-', '', '') WHERE status ~ '^queued-';

UPDATE admin SET status = 'queued' WHERE status ~ '^queued-';

COMMIT;
