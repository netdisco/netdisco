BEGIN;

CREATE TABLE "device_skip" (
  "backend" text NOT NULL,
  "device" inet NOT NULL,
  "actionset" text[] DEFAULT '{}',
  "deferrals" integer DEFAULT 0,
  "skipover" boolean DEFAULT false,
  PRIMARY KEY ("backend", "device")
);

COMMIT;
