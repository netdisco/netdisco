BEGIN;

ALTER TABLE device ADD COLUMN "custom_fields" jsonb DEFAULT '{}';

UPDATE device SET custom_fields = '{}';

COMMIT;
