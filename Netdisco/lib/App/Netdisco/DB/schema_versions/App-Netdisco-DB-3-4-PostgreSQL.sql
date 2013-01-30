-- Convert schema '/home/oliver/git/netdisco-frontend-sandpit/Netdisco/bin/../lib/App/Netdisco/DB/schema_versions/App-Netdisco-DB-3-PostgreSQL.sql' to '/home/oliver/git/netdisco-frontend-sandpit/Netdisco/bin/../lib/App/Netdisco/DB/schema_versions/App-Netdisco-DB-4-PostgreSQL.sql':;

BEGIN;

ALTER TABLE node DROP CONSTRAINT node_pkey;

ALTER TABLE node_wireless DROP CONSTRAINT node_wireless_pkey;

ALTER TABLE node ADD COLUMN vlan text DEFAULT '0' NOT NULL;

ALTER TABLE node_wireless ADD COLUMN ssid text DEFAULT '' NOT NULL;

CREATE INDEX device_port_power_idx_ip_port on device_port_power (ip, port);

ALTER TABLE admin ADD PRIMARY KEY (job);

ALTER TABLE node ADD PRIMARY KEY (mac, switch, port, vlan);

ALTER TABLE node_wireless ADD PRIMARY KEY (mac, ssid);

COMMIT;

