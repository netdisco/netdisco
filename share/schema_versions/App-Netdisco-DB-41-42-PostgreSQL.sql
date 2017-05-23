BEGIN;

CREATE TABLE "device_skip" (
  "backend" text NOT NULL,
  "device" inet NOT NULL,
  "actionset" text[] DEFAULT '{}',
  "deferrals" integer DEFAULT 0,
  PRIMARY KEY ("backend", "device")
);

COMMIT;
