BEGIN;

DROP INDEX IF EXISTS idx_device_browser_ip_leaf;

ALTER TABLE device_browser DROP COLUMN leaf;

ALTER TABLE device_browser DROP COLUMN munge;

CREATE TABLE snmp_filter (
    "leaf"    "text" NOT NULL,
    "subname"    "text" NOT NULL,
    PRIMARY KEY ("leaf")
);

COMMIT;
