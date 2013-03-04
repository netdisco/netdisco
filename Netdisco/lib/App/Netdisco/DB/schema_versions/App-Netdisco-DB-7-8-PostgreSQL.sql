-- Convert schema '/home/sy0/git/netdisco-frontend-sandpit/Netdisco/lib/Netdisco/DB/schema_versions/Netdisco-DB-1-PostgreSQL.sql' to '/home/sy0/git/netdisco-frontend-sandpit/Netdisco/lib/Netdisco/DB/schema_versions/Netdisco-DB-2-PostgreSQL.sql':;

BEGIN;

ALTER TABLE node_ip ADD COLUMN dns text;

COMMIT;

