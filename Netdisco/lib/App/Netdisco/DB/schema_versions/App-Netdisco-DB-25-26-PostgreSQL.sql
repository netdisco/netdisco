BEGIN;

-- ALTER TABLE device_port ALTER COLUMN remote_id TYPE bytea USING remote_id::bytea;

COMMIT;
