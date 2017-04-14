BEGIN;

-- ALTER TABLE device_port ALTER COLUMN remote_id TYPE text USING remote_id::text;

COMMIT;
