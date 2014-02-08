BEGIN;

-- Netdisco
-- Database Schema Modifications
-- UPGRADE from 0.94 to 0.95

CREATE TABLE subnets (
    net cidr NOT NULL,
    creation timestamp default now(),
    last_discover timestamp default now(),
    PRIMARY KEY(net)
);

--
-- node_nbt could already exist, if you upgraded to 0.94, but if
-- you ran pg_all in 0.94, node_nbt wasn't created.  This
-- will report some harmless errors if it already exists.

CREATE TABLE node_nbt (
    mac         macaddr PRIMARY KEY,
    ip          inet,
    nbname      text,
    domain      text,
    server      boolean,
    nbuser      text,
    active      boolean,    -- do we need this still?
    time_first  timestamp default now(),
    time_last   timestamp default now()
);

-- Indexing speed ups.
CREATE INDEX idx_node_nbt_mac         ON node_nbt(mac);
CREATE INDEX idx_node_nbt_nbname      ON node_nbt(nbname);
CREATE INDEX idx_node_nbt_domain      ON node_nbt(domain);
CREATE INDEX idx_node_nbt_mac_active  ON node_nbt(mac,active);

--
-- Add time_recent to node table
ALTER TABLE node ADD time_recent timestamp;
ALTER TABLE node ALTER time_recent SET DEFAULT now();
UPDATE node SET time_recent = time_first WHERE time_recent IS NULL;

--
-- Add table to contain wireless base station SSIDs
CREATE TABLE device_port_ssid (
    ip          inet,   -- ip of device
    port        text,   -- Unique identifier of Physical Port Name
    ssid        text,   -- An SSID that is valid on this port.
    broadcast   boolean,-- Is it broadcast?
    channel     integer -- 802.11 channel number
);

CREATE INDEX idx_device_port_ssid_ip_port ON device_port_ssid(ip,port);

--
-- The OUI field in the oui database is now lowercase.
UPDATE oui SET oui=lower(oui);

COMMIT;
