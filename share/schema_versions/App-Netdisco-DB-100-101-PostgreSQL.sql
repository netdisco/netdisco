BEGIN;

-- Schema 101 drops indexes that another index or the primary key already
-- covers and adds four that existing queries lack.

DROP INDEX IF EXISTS node_ip_idx_ip_active;
DROP INDEX IF EXISTS idx_node_ip_ip;
DROP INDEX IF EXISTS idx_node_ip_mac;
DROP INDEX IF EXISTS idx_node_mac;
DROP INDEX IF EXISTS idx_node_switch;
DROP INDEX IF EXISTS idx_node_switch_port;
DROP INDEX IF EXISTS idx_device_port_ip;
DROP INDEX IF EXISTS idx_device_ip_ip;
DROP INDEX IF EXISTS idx_node_nbt_mac;
DROP INDEX IF EXISTS idx_device_port_wireless_ip_port;

CREATE INDEX IF NOT EXISTS idx_device_port_properties_ip_port ON device_port_properties (ip, port);
CREATE INDEX IF NOT EXISTS idx_node_nbt_ip ON node_nbt (ip);
CREATE INDEX IF NOT EXISTS idx_admin_device ON admin (device);
CREATE INDEX IF NOT EXISTS idx_node_oui ON node (oui);

COMMIT;
