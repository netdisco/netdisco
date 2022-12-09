BEGIN;

ALTER TABLE device ADD COLUMN "custom_fields" jsonb DEFAULT '{}';

UPDATE device SET custom_fields = '{}';

ALTER TABLE device_port ADD COLUMN "custom_fields" jsonb DEFAULT '{}';

UPDATE device_port SET custom_fields = '{}';

COMMIT;
