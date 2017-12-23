BEGIN;

CREATE TABLE "netmap_positions" (
  "id" serial PRIMARY KEY,
  "device_groups" text[] NOT NULL,
  "vlan" integer NOT NULL DEFAULT 0,
  "positions" text NOT NULL,
  UNIQUE ("device_groups", "vlan")
);

COMMIT;
