BEGIN;

ALTER TABLE node ADD PRIMARY KEY (mac, switch, port, vlan);

COMMIT;
