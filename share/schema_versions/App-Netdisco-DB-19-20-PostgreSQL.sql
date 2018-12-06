BEGIN;

ALTER TABLE node_wireless ADD PRIMARY KEY (mac, ssid);

COMMIT;
