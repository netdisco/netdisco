BEGIN;

CREATE INDEX device_port_power_idx_ip_port on device_port_power (ip, port);

COMMIT;
