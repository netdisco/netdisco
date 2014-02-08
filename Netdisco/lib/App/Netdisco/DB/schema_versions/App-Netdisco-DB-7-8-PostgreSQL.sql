BEGIN;

-- Netdisco
-- Database Schema Modifications
-- UPGRADE from 1.1 to 1.2

-- Add "vlantype" column to device_port_vlan table
ALTER TABLE device_port_vlan ADD vlantype text;

-- Add "topology" table to augment manual topo file
CREATE TABLE topology (
    dev1   inet not null,
    port1  text not null,
    dev2   inet not null,
    port2  text not null
);

-- Add "bssid" column to device_port_ssid table
ALTER TABLE device_port_ssid ADD bssid macaddr;

-- Add "vlan" column to node table
ALTER TABLE node ADD vlan text DEFAULT '0';

ALTER TABLE node DROP CONSTRAINT node_pkey;
ALTER TABLE node ADD PRIMARY KEY key (mac, switch, port, vlan);

-- Add "ssid" column to node_wireless table
ALTER TABLE node_wireless ADD ssid text DEFAULT '';

ALTER TABLE node_wireless DROP CONSTRAINT node_wireless_pkey;
ALTER TABLE node_wireless ADD PRIMARY KEY (mac, ssid);

COMMIT;
