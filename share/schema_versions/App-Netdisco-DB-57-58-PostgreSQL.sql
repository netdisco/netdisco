BEGIN;

ALTER TABLE device_port_wireless ALTER COLUMN ip SET NOT NULL;

ALTER TABLE device_port_wireless ALTER COLUMN port SET NOT NULL;

ALTER TABLE device_port_wireless ADD CONSTRAINT device_port_wireless_pkey PRIMARY KEY (ip, port);

ALTER TABLE device_port_ssid ALTER COLUMN ip SET NOT NULL;

ALTER TABLE device_port_ssid ALTER COLUMN port SET NOT NULL;

ALTER TABLE device_port_ssid ALTER COLUMN bssid SET NOT NULL;

ALTER TABLE device_port_ssid ADD CONSTRAINT device_port_ssid_pkey PRIMARY KEY (ip, bssid, port);

ALTER TABLE device_port_log ADD PRIMARY KEY (id);

COMMIT;
