BEGIN;

CREATE TABLE device_browser (
    "ip"     "inet" NOT NULL,
    "oid"    "text" NOT NULL,
    "oid_parts" integer[] NOT NULL,
    "leaf"   "text" NOT NULL,
    "value"  "text",
    PRIMARY KEY ("ip", "oid")
);

CREATE INDEX idx_device_browser_ip_leaf ON device_browser(ip, leaf);

COMMIT;
