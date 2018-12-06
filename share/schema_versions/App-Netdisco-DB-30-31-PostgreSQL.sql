BEGIN;

ALTER TABLE node_wireless ALTER COLUMN rxpkt TYPE bigint;
ALTER TABLE node_wireless ALTER COLUMN txpkt TYPE bigint;
ALTER TABLE node_wireless ALTER COLUMN rxbyte TYPE bigint;
ALTER TABLE node_wireless ALTER COLUMN txbyte TYPE bigint;

COMMIT;
