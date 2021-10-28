BEGIN;

CREATE TABLE snmp_object (
    "oid"    integer[] NOT NULL,
    "mib"    "text" NOT NULL,
    "leaf"   "text" NOT NULL,
    "type"   "text",
    "munge"  "text",
    "access" "text",
    "index"  text[] DEFAULT '{}',
    PRIMARY KEY ("oid")
);

COMMIT;
