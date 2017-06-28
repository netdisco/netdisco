BEGIN;

CREATE TABLE "statistics" (
  "day" date NOT NULL DEFAULT CURRENT_DATE,

  "device_count" integer NOT NULL,
  "device_ip_count" integer NOT NULL,
  "device_link_count" integer NOT NULL,
  "device_port_count" integer NOT NULL,
  "device_port_up_count" integer NOT NULL,
  "ip_table_count" integer NOT NULL,
  "ip_active_count" integer NOT NULL,
  "node_table_count" integer NOT NULL,
  "node_active_count" integer NOT NULL,

  "netdisco_ver" text,
  "snmpinfo_ver" text,
  "schema_ver" text,
  "perl_ver" text,
  "pg_ver" text,

  PRIMARY KEY ("day")
);

COMMIT;
