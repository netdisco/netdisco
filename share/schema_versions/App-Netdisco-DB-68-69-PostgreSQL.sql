BEGIN;

CREATE TABLE device_browser (
    "ip"     "inet" NOT NULL,
    "oid"    "text" NOT NULL,
    "mib"    "text" NOT NULL,
    "leaf"   "text" NOT NULL,
    "type"   "text",
    "munge"  "text",
    "access" "text",
    "index"  text[] DEFAULT '{}',
    "value"  "text",
    PRIMARY KEY ("ip", "oid")
);

CREATE INDEX idx_device_browser_ip_leaf ON device_browser(ip, leaf);

COMMIT;
