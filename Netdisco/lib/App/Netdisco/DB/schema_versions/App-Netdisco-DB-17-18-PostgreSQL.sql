-- Convert schema '/home/devver/netdisco-ng/Netdisco/bin/../lib/App/Netdisco/DB/schema_versions/App-Netdisco-DB-17-PostgreSQL.sql' to '/home/devver/netdisco-ng/Netdisco/bin/../lib/App/Netdisco/DB/schema_versions/App-Netdisco-DB-18-PostgreSQL.sql':;

BEGIN;

ALTER TABLE topology ADD CONSTRAINT topology_dev1_port1 UNIQUE (dev1, port1);

ALTER TABLE topology ADD CONSTRAINT topology_dev2_port2 UNIQUE (dev2, port2);

COMMIT;

