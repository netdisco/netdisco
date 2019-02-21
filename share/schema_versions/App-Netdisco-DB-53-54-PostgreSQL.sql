BEGIN;

ALTER TABLE device_port ADD COLUMN "ifindex" bigint;

COMMIT;
