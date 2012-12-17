-- Convert schema '/home/sy0/git/netdisco-frontend-sandpit/Netdisco/lib/Netdisco/DB/schema_versions/Netdisco-DB-1-PostgreSQL.sql' to '/home/sy0/git/netdisco-frontend-sandpit/Netdisco/lib/Netdisco/DB/schema_versions/Netdisco-DB-2-PostgreSQL.sql':;

BEGIN;

CREATE TABLE "topology" (
  "dev1" inet NOT NULL,
  "port1" text NOT NULL,
  "dev2" inet NOT NULL,
  "port2" text NOT NULL
);

ALTER TABLE device_port_ssid ADD COLUMN bssid macaddr;

ALTER TABLE device_port_vlan ADD COLUMN vlantype text;

ALTER TABLE node_ip ADD COLUMN dns text;

COMMIT;

