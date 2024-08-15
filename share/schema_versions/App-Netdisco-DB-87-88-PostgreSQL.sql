BEGIN;

ALTER TABLE statistics ADD COLUMN python_ver text;

COMMIT;
