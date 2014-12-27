BEGIN;

-- Add/Alter tables to support stp topology
--
-- Table: device_stp.
--
CREATE TABLE "device_stp" (
  "ip" inet NOT NULL,
  "instance" integer NOT NULL,
  "mac" macaddr,
  "top_change" integer,
  "top_lastchange" bigint,
  "des_root_mac" macaddr,
  "root_port" text,
  PRIMARY KEY ("ip", "instance")
);
CREATE INDEX "device_stp_idx_ip" on "device_stp" ("ip");
CREATE INDEX "device_stp_idx_des_root_mac" on "device_stp" ("des_root_mac");

--
-- Table: device_port_stp.
--
CREATE TABLE "device_port_stp" (
  "ip" inet NOT NULL,
  "port" text NOT NULL,
  "instance" integer NOT NULL,
  "port_id" integer NOT NULL,
  "des_bridge_mac" macaddr,
  "des_port_id" integer,
  "status" text,
  PRIMARY KEY ("ip", "port", "instance")
);
CREATE INDEX "device_port_stp_idx_ip_instance" on "device_port_stp" ("ip", "instance");
CREATE INDEX "device_port_stp_idx_ip_port" on "device_port_stp" ("ip", "port");
CREATE INDEX "device_port_stp_idx_port_id" on "device_port_stp" ("port_id");
CREATE INDEX "device_port_stp_idx_mac" on "device_port_stp" ("des_bridge_mac");

--
-- Alter Table: device
--
ALTER TABLE device ADD COLUMN "stp_ver" text;
-- existing mac may not be the bridge base mac
ALTER TABLE device ADD COLUMN "b_mac" macaddr;
CREATE INDEX "device_idx_b_mac" on "device" ("b_mac");

COMMIT;
