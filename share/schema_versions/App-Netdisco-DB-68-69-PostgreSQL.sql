BEGIN;

CREATE TABLE device_browser (
    "ip"     "inet" NOT NULL,
    "oid"    "text" NOT NULL,
    "oid_parts" integer[] NOT NULL,
    "leaf"   "text" NOT NULL,
    "munge"  "text",
    "value"  "text",
    PRIMARY KEY ("ip", "oid")
);

CREATE INDEX idx_device_browser_ip_leaf ON device_browser(ip, leaf);

CREATE INDEX idx_device_browser_oid__pattern on device_browser (oid text_pattern_ops);

COMMIT;
