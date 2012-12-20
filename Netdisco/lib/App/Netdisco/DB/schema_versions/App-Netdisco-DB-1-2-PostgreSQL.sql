-- 
-- Created by SQL::Translator::Producer::PostgreSQL
-- Created on Wed Oct 10 14:24:20 2012
-- 
--
-- Table: admin.
--
CREATE TABLE "admin" (
  "job" serial NOT NULL,
  "entered" timestamp DEFAULT current_timestamp,
  "started" timestamp,
  "finished" timestamp,
  "device" inet,
  "port" text,
  "action" text,
  "subaction" text,
  "status" text,
  "username" text,
  "userip" inet,
  "log" text,
  "debug" boolean
);

--
-- Table: device.
--
CREATE TABLE "device" (
  "ip" inet NOT NULL,
  "creation" timestamp DEFAULT current_timestamp,
  "dns" text,
  "description" text,
  "uptime" bigint,
  "contact" text,
  "name" text,
  "location" text,
  "layers" character varying(8),
  "ports" integer,
  "mac" macaddr,
  "serial" text,
  "model" text,
  "ps1_type" text,
  "ps2_type" text,
  "ps1_status" text,
  "ps2_status" text,
  "fan" text,
  "slots" integer,
  "vendor" text,
  "os" text,
  "os_ver" text,
  "log" text,
  "snmp_ver" integer,
  "snmp_comm" text,
  "snmp_class" text,
  "vtp_domain" text,
  "last_discover" timestamp,
  "last_macsuck" timestamp,
  "last_arpnip" timestamp,
  PRIMARY KEY ("ip")
);

--
-- Table: device_module.
--
CREATE TABLE "device_module" (
  "ip" inet NOT NULL,
  "index" integer NOT NULL,
  "description" text,
  "type" text,
  "parent" integer,
  "name" text,
  "class" text,
  "pos" integer,
  "hw_ver" text,
  "fw_ver" text,
  "sw_ver" text,
  "serial" text,
  "model" text,
  "fru" boolean,
  "creation" timestamp DEFAULT current_timestamp,
  "last_discover" timestamp,
  PRIMARY KEY ("ip", "index")
);

--
-- Table: device_port_log.
--
CREATE TABLE "device_port_log" (
  "id" serial NOT NULL,
  "ip" inet,
  "port" text,
  "reason" text,
  "log" text,
  "username" text,
  "userip" inet,
  "action" text,
  "creation" timestamp DEFAULT current_timestamp
);

--
-- Table: device_port_power.
--
CREATE TABLE "device_port_power" (
  "ip" inet NOT NULL,
  "port" text NOT NULL,
  "module" integer,
  "admin" text,
  "status" text,
  "class" text,
  "power" integer,
  PRIMARY KEY ("port", "ip")
);

--
-- Table: device_port_ssid.
--
CREATE TABLE "device_port_ssid" (
  "ip" inet,
  "port" text,
  "ssid" text,
  "broadcast" boolean
);

--
-- Table: device_port_wireless.
--
CREATE TABLE "device_port_wireless" (
  "ip" inet,
  "port" text,
  "channel" integer,
  "power" integer
);

--
-- Table: device_power.
--
CREATE TABLE "device_power" (
  "ip" inet NOT NULL,
  "module" integer NOT NULL,
  "power" integer,
  "status" text,
  PRIMARY KEY ("ip", "module")
);

--
-- Table: device_route.
--
CREATE TABLE "device_route" (
  "ip" inet NOT NULL,
  "network" cidr NOT NULL,
  "creation" timestamp DEFAULT current_timestamp,
  "dest" inet NOT NULL,
  "last_discover" timestamp DEFAULT current_timestamp,
  PRIMARY KEY ("ip", "network", "dest")
);

--
-- Table: log.
--
CREATE TABLE "log" (
  "id" serial NOT NULL,
  "creation" timestamp DEFAULT current_timestamp,
  "class" text,
  "entry" text,
  "logfile" text
);

--
-- Table: node_ip.
--
CREATE TABLE "node_ip" (
  "mac" macaddr NOT NULL,
  "ip" inet NOT NULL,
  "active" boolean,
  "time_first" timestamp DEFAULT current_timestamp,
  "time_last" timestamp DEFAULT current_timestamp,
  PRIMARY KEY ("mac", "ip")
);

--
-- Table: node_monitor.
--
CREATE TABLE "node_monitor" (
  "mac" macaddr NOT NULL,
  "active" boolean,
  "why" text,
  "cc" text,
  "date" timestamp DEFAULT current_timestamp,
  PRIMARY KEY ("mac")
);

--
-- Table: node_nbt.
--
CREATE TABLE "node_nbt" (
  "mac" macaddr NOT NULL,
  "ip" inet,
  "nbname" text,
  "domain" text,
  "server" boolean,
  "nbuser" text,
  "active" boolean,
  "time_first" timestamp DEFAULT current_timestamp,
  "time_last" timestamp DEFAULT current_timestamp,
  PRIMARY KEY ("mac")
);

--
-- Table: node_wireless.
--
CREATE TABLE "node_wireless" (
  "mac" macaddr NOT NULL,
  "uptime" integer,
  "maxrate" integer,
  "txrate" integer,
  "sigstrength" integer,
  "sigqual" integer,
  "rxpkt" integer,
  "txpkt" integer,
  "rxbyte" bigint,
  "txbyte" bigint,
  "time_last" timestamp DEFAULT current_timestamp,
  PRIMARY KEY ("mac")
);

--
-- Table: oui.
--
CREATE TABLE "oui" (
  "oui" character varying(8) NOT NULL,
  "company" text,
  PRIMARY KEY ("oui")
);

--
-- Table: process.
--
CREATE TABLE "process" (
  "controller" integer NOT NULL,
  "device" inet NOT NULL,
  "action" text NOT NULL,
  "status" text,
  "count" integer,
  "creation" timestamp DEFAULT current_timestamp
);

--
-- Table: sessions.
--
CREATE TABLE "sessions" (
  "id" character(32) NOT NULL,
  "creation" timestamp DEFAULT current_timestamp,
  "a_session" text,
  PRIMARY KEY ("id")
);

--
-- Table: subnets.
--
CREATE TABLE "subnets" (
  "net" cidr NOT NULL,
  "creation" timestamp DEFAULT current_timestamp,
  "last_discover" timestamp DEFAULT current_timestamp,
  PRIMARY KEY ("net")
);

--
-- Table: user_log.
--
CREATE TABLE "user_log" (
  "entry" serial NOT NULL,
  "username" character varying(50),
  "userip" inet,
  "event" text,
  "details" text,
  "creation" timestamp DEFAULT current_timestamp
);

--
-- Table: users.
--
CREATE TABLE "users" (
  "username" character varying(50) NOT NULL,
  "password" text,
  "creation" timestamp DEFAULT current_timestamp,
  "last_on" timestamp,
  "port_control" boolean DEFAULT false,
  "ldap" boolean DEFAULT false,
  "admin" boolean DEFAULT false,
  "fullname" text,
  "note" text,
  PRIMARY KEY ("username")
);

--
-- Table: device_vlan.
--
CREATE TABLE "device_vlan" (
  "ip" inet NOT NULL,
  "vlan" integer NOT NULL,
  "description" text,
  "creation" timestamp DEFAULT current_timestamp,
  "last_discover" timestamp DEFAULT current_timestamp,
  PRIMARY KEY ("ip", "vlan")
);
CREATE INDEX "device_vlan_idx_ip" on "device_vlan" ("ip");

--
-- Table: device_ip.
--
CREATE TABLE "device_ip" (
  "ip" inet NOT NULL,
  "alias" inet NOT NULL,
  "subnet" cidr,
  "port" text,
  "dns" text,
  "creation" timestamp DEFAULT current_timestamp,
  PRIMARY KEY ("ip", "alias"),
  CONSTRAINT "device_ip_alias" UNIQUE ("alias")
);
CREATE INDEX "device_ip_idx_ip" on "device_ip" ("ip");
CREATE INDEX "device_ip_idx_ip_port" on "device_ip" ("ip", "port");

--
-- Table: device_port.
--
CREATE TABLE "device_port" (
  "ip" inet NOT NULL,
  "port" text NOT NULL,
  "creation" timestamp DEFAULT current_timestamp,
  "descr" text,
  "up" text,
  "up_admin" text,
  "type" text,
  "duplex" text,
  "duplex_admin" text,
  "speed" text,
  "name" text,
  "mac" macaddr,
  "mtu" integer,
  "stp" text,
  "remote_ip" inet,
  "remote_port" text,
  "remote_type" text,
  "remote_id" text,
  "vlan" text,
  "pvid" integer,
  "lastchange" bigint,
  PRIMARY KEY ("port", "ip")
);
CREATE INDEX "device_port_idx_ip" on "device_port" ("ip");
CREATE INDEX "device_port_idx_remote_ip" on "device_port" ("remote_ip");

--
-- Table: device_port_vlan.
--
CREATE TABLE "device_port_vlan" (
  "ip" inet NOT NULL,
  "port" text NOT NULL,
  "vlan" integer NOT NULL,
  "native" boolean DEFAULT false NOT NULL,
  "creation" timestamp DEFAULT current_timestamp,
  "last_discover" timestamp DEFAULT current_timestamp,
  PRIMARY KEY ("ip", "port", "vlan")
);
CREATE INDEX "device_port_vlan_idx_ip" on "device_port_vlan" ("ip");
CREATE INDEX "device_port_vlan_idx_ip_port" on "device_port_vlan" ("ip", "port");
CREATE INDEX "device_port_vlan_idx_ip_vlan" on "device_port_vlan" ("ip", "vlan");

--
-- Table: node.
--
CREATE TABLE "node" (
  "mac" macaddr NOT NULL,
  "switch" inet NOT NULL,
  "port" text NOT NULL,
  "active" boolean,
  "oui" character varying(8),
  "time_first" timestamp DEFAULT current_timestamp,
  "time_recent" timestamp DEFAULT current_timestamp,
  "time_last" timestamp DEFAULT current_timestamp,
  PRIMARY KEY ("mac", "switch", "port")
);
CREATE INDEX "node_idx_switch" on "node" ("switch");
CREATE INDEX "node_idx_switch_port" on "node" ("switch", "port");
CREATE INDEX "node_idx_oui" on "node" ("oui");

-- Not used in Netdisco, because they upset the legacy netdisco.pm code
-- 
-- --
-- -- Foreign Key Definitions
-- --
-- 
-- ALTER TABLE "device_vlan" ADD CONSTRAINT "device_vlan_fk_ip" FOREIGN KEY ("ip")
--   REFERENCES "device" ("ip") ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE;
-- 
-- ALTER TABLE "device_ip" ADD CONSTRAINT "device_ip_fk_ip" FOREIGN KEY ("ip")
--   REFERENCES "device" ("ip") ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE;
-- 
-- ALTER TABLE "device_ip" ADD CONSTRAINT "device_ip_fk_ip_port" FOREIGN KEY ("ip", "port")
--   REFERENCES "device_port" ("ip", "port") DEFERRABLE;
-- 
-- ALTER TABLE "device_port" ADD CONSTRAINT "device_port_fk_ip" FOREIGN KEY ("ip")
--   REFERENCES "device" ("ip") ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE;
-- 
-- ALTER TABLE "device_port" ADD CONSTRAINT "device_port_fk_remote_ip" FOREIGN KEY ("remote_ip")
--   REFERENCES "device_ip" ("alias") DEFERRABLE;
-- 
-- ALTER TABLE "device_port_vlan" ADD CONSTRAINT "device_port_vlan_fk_ip" FOREIGN KEY ("ip")
--   REFERENCES "device" ("ip") ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE;
-- 
-- ALTER TABLE "device_port_vlan" ADD CONSTRAINT "device_port_vlan_fk_ip_port" FOREIGN KEY ("ip", "port")
--   REFERENCES "device_port" ("ip", "port") DEFERRABLE;
-- 
-- ALTER TABLE "device_port_vlan" ADD CONSTRAINT "device_port_vlan_fk_ip_vlan" FOREIGN KEY ("ip", "vlan")
--   REFERENCES "device_vlan" ("ip", "vlan") DEFERRABLE;
-- 
-- ALTER TABLE "node" ADD CONSTRAINT "node_fk_switch" FOREIGN KEY ("switch")
--   REFERENCES "device" ("ip") DEFERRABLE;
-- 
-- ALTER TABLE "node" ADD CONSTRAINT "node_fk_switch_port" FOREIGN KEY ("switch", "port")
--   REFERENCES "device_port" ("ip", "port") ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE;
-- 
-- ALTER TABLE "node" ADD CONSTRAINT "node_fk_oui" FOREIGN KEY ("oui")
--   REFERENCES "oui" ("oui") DEFERRABLE;
-- 
