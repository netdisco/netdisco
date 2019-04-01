BEGIN;

ALTER TABLE device_port_vlan ADD COLUMN "egress_tag" boolean not null default false;

COMMIT;
