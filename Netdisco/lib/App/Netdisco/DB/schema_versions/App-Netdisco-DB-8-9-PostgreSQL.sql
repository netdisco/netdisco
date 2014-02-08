BEGIN;

CREATE TABLE "topology" (
  "dev1" inet NOT NULL,
  "port1" text NOT NULL,
  "dev2" inet NOT NULL,
  "port2" text NOT NULL
);

COMMIT;
