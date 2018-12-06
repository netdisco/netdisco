BEGIN;

ALTER TABLE "device_skip" ADD "last_defer" timestamp;

COMMIT;
