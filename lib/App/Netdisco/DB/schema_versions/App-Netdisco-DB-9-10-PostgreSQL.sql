BEGIN;

ALTER TABLE device_port_ssid ADD COLUMN bssid macaddr;

COMMIT;
