BEGIN;

CREATE TABLE device_snapshot (
    "ip"    "inet",
    "cache" "text",
    PRIMARY KEY ("ip")
);

COMMIT;
