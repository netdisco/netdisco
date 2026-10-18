BEGIN;

ALTER TABLE device ADD COLUMN "custom_fields" jsonb DEFAULT '{}';

UPDATE device SET custom_fields = '{}' WHERE custom_fields IS NULL;

ALTER TABLE device_port ADD COLUMN "custom_fields" jsonb DEFAULT '{}';

UPDATE device_port SET custom_fields = '{}' WHERE custom_fields IS NULL;

COMMIT;
