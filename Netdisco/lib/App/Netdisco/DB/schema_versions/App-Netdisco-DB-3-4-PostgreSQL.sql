BEGIN;

-- Netdisco
-- Database Schema Modifications
-- UPGRADE from 0.93 to 0.94

ALTER TABLE device_port ADD COLUMN lastchange bigint;

ALTER TABLE log ADD COLUMN logfile text;

CREATE TABLE user_log (
    entry           serial,
    username        varchar(50),
    userip          inet,
    event           text,
    details         text,
    creation        TIMESTAMP DEFAULT now()
                      );

CREATE TABLE node_nbt (
    mac         macaddr PRIMARY KEY,
    ip          inet,
    nbname      text,
    domain      text,
    server      boolean,
    nbuser      text,
    active      boolean,
    time_first  timestamp default now(),
    time_last   timestamp default now()
);

-- Indexing speed ups.
CREATE INDEX idx_node_nbt_mac         ON node_nbt(mac);
CREATE INDEX idx_node_nbt_nbname      ON node_nbt(nbname);
CREATE INDEX idx_node_nbt_domain      ON node_nbt(domain);
CREATE INDEX idx_node_nbt_mac_active  ON node_nbt(mac,active);

COMMIT;
