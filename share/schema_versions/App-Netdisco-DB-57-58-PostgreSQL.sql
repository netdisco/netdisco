BEGIN;

ALTER TABLE device_port_wireless ALTER COLUMN ip SET NOT NULL;

ALTER TABLE device_port_wireless ALTER COLUMN port SET NOT NULL;

ALTER TABLE device_port_wireless ADD CONSTRAINT device_port_wireless_pkey PRIMARY KEY (ip, port);

-- rows the new key rejects are stale: discover replaces a device's SSIDs
DELETE FROM device_port_ssid WHERE ip IS NULL OR port IS NULL OR bssid IS NULL;

DELETE FROM device_port_ssid a USING device_port_ssid b
  WHERE a.ip = b.ip AND a.port = b.port AND a.bssid = b.bssid AND a.ctid < b.ctid;

ALTER TABLE device_port_ssid ALTER COLUMN ip SET NOT NULL;

ALTER TABLE device_port_ssid ALTER COLUMN port SET NOT NULL;

ALTER TABLE device_port_ssid ALTER COLUMN bssid SET NOT NULL;

ALTER TABLE device_port_ssid ADD CONSTRAINT device_port_ssid_pkey PRIMARY KEY (ip, bssid, port);

ALTER TABLE device_port_log ADD PRIMARY KEY (id);

COMMIT;
