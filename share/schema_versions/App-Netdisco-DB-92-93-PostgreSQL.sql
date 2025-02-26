BEGIN;

DROP TABLE device_snapshot;

ALTER TABLE device_browser ALTER COLUMN value TYPE JSONB USING to_json(value);

ALTER TABLE device_browser  ALTER COLUMN value SET DEFAULT '[]';

COMMIT;
