
BEGIN;

ALTER TABLE device_port_vlan DROP CONSTRAINT device_port_vlan_pkey;

ALTER TABLE device_port_vlan ADD PRIMARY KEY (ip, port, vlan, native);

COMMIT;
