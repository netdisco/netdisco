-- Convert schema '/home/oliver/git/netdisco-frontend-sandpit/Netdisco/bin/../lib/App/Netdisco/DB/schema_versions/App-Netdisco-DB-3-PostgreSQL.sql' to '/home/oliver/git/netdisco-frontend-sandpit/Netdisco/bin/../lib/App/Netdisco/DB/schema_versions/App-Netdisco-DB-4-PostgreSQL.sql':;

BEGIN;

CREATE INDEX device_port_power_idx_ip_port on device_port_power (ip, port);

COMMIT;

