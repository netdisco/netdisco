BEGIN;

CREATE TABLE snmp_filter (
    "leaf"    "text" NOT NULL,
    "subname"    "text" NOT NULL,
    PRIMARY KEY ("leaf")
);

COMMIT;
