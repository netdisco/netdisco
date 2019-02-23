BEGIN;

ALTER TABLE device_port_properties ADD COLUMN "ifindex" bigint;

COMMIT;
