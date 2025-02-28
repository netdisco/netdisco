BEGIN;

DROP TABLE device_snapshot;

ALTER TABLE device_browser ALTER COLUMN value TYPE JSONB USING cast('"' || regexp_replace(value, E'([\\n\\r]+)|([\\n\\r]+)', '', 'g' ) || '"' AS json);

ALTER TABLE device_browser  ALTER COLUMN value SET DEFAULT '[""]';

COMMIT;
