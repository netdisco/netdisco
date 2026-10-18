BEGIN;

ALTER TABLE statistics ADD COLUMN phone_count integer NOT NULL DEFAULT 0;

ALTER TABLE statistics ADD COLUMN wap_count integer NOT NULL DEFAULT 0;

COMMIT;
