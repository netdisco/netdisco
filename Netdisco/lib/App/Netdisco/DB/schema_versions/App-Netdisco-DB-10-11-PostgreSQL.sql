BEGIN;

ALTER TABLE device_port_vlan ADD COLUMN vlantype text;

COMMIT;
