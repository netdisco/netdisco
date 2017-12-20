BEGIN;

CREATE TABLE "netmap_positions" (
  "id" serial PRIMARY KEY,
  "device_groups" text[] UNIQUE NOT NULL,
  "positions" text NOT NULL
);

COMMIT;
