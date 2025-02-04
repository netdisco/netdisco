BEGIN;

ALTER TABLE statistics ADD COLUMN phone_count integer NOT NULL DEFAULT 0;

UPDATE statistics SET phone_count = 0;

ALTER TABLE statistics ADD COLUMN wap_count integer NOT NULL DEFAULT 0;

UPDATE statistics SET wap_count = 0;

COMMIT;
