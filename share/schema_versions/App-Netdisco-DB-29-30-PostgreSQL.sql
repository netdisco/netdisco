BEGIN;

CREATE TABLE "community" (
  "ip" inet NOT NULL,
  "snmp_comm_rw" text,
  PRIMARY KEY ("ip")
);

COMMIT;
