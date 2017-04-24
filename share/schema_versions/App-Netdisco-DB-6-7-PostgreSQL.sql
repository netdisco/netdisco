BEGIN;

-- Netdisco
-- Database Schema Modifications
-- UPGRADE from 1.0 to 1.1

--
-- Add index to node_ip table
CREATE INDEX idx_node_ip_ip_active ON node_ip(ip,active);

-- Add "power" column to device_port_power table
ALTER TABLE device_port_power ADD power integer;

COMMIT;
