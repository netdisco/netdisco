BEGIN;

ALTER TABLE device_ip DROP CONSTRAINT "device_ip_alias";

COMMIT;
