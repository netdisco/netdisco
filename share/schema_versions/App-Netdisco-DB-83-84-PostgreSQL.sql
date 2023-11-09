BEGIN;

ALTER TABLE netmap_positions ADD COLUMN "depth" integer DEFAULT 0 NOT NULL;

UPDATE netmap_positions SET depth = 0 WHERE device IS NOT NULL;

COMMIT;
