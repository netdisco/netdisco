BEGIN;

CREATE TABLE "device_skip" (
  "backend" text NOT NULL,
  "device" inet NOT NULL,
  "action" text NOT NULL,
  "failures" integer DEFAULT 0,
  "skipover" boolean DEFAULT false,
  PRIMARY KEY ("backend", "device", "action")
);

COMMIT;
