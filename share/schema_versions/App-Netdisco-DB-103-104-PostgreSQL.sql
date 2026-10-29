BEGIN;

SET LOCAL client_min_messages = warning;

ALTER TABLE device_ip ADD COLUMN IF NOT EXISTS first_seen timestamp;
ALTER TABLE device_ip ALTER COLUMN first_seen SET DEFAULT LOCALTIMESTAMP;
ALTER TABLE device_port ADD COLUMN IF NOT EXISTS first_seen timestamp;
ALTER TABLE device_port ALTER COLUMN first_seen SET DEFAULT LOCALTIMESTAMP;

COMMIT;
