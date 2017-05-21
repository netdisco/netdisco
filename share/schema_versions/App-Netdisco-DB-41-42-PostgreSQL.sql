BEGIN;

CREATE TABLE "device_ignore" (
  "backend" text NOT NULL,
  "device" inet NOT NULL,
  "action" text NOT NULL,
  "failures" integer DEFAULT 0,
  "ignore" boolean DEFAULT false,
  PRIMARY KEY ("backend", "device", "action")
);

COMMIT;
