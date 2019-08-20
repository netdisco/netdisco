BEGIN;

ALTER TABLE device_port_vlan ADD COLUMN "egress_tag" boolean not null default true;

UPDATE device_port_vlan SET egress_tag = true;

UPDATE device_port_vlan SET egress_tag = false WHERE native = TRUE;

COMMIT;
