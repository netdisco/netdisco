BEGIN;

ALTER TABLE device ADD COLUMN "chassis_id" text;

COMMIT;
