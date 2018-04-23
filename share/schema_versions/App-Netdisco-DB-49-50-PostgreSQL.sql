BEGIN;

ALTER TABLE node_monitor ADD COLUMN "matchoui" boolean;

COMMIT;
