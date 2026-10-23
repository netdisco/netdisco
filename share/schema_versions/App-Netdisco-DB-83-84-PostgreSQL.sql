BEGIN;

ALTER TABLE netmap_positions ADD COLUMN "depth" integer DEFAULT 0 NOT NULL;

COMMIT;
