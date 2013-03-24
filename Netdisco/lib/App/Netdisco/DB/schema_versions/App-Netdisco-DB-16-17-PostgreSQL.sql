-- Convert schema '/home/devver/netdisco-ng/Netdisco/bin/../lib/App/Netdisco/DB/schema_versions/App-Netdisco-DB-16-PostgreSQL.sql' to '/home/devver/netdisco-ng/Netdisco/bin/../lib/App/Netdisco/DB/schema_versions/App-Netdisco-DB-17-PostgreSQL.sql':;

BEGIN;

ALTER TABLE admin ADD CONSTRAINT queued_job UNIQUE (device, action, subaction);

COMMIT;

