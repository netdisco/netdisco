BEGIN;

CREATE TABLE device_port_properties (
    "ip"     "inet",
    "port"   "text",
    "error_disable_cause"  "text",
    PRIMARY KEY ("port", "ip")
);

COMMIT;
