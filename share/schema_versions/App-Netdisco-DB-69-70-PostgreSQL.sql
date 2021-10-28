BEGIN;

CREATE TABLE snmp_oid_meta (
    "oid"    "text" NOT NULL,
    "mib"    "text" NOT NULL,
    "leaf"   "text" NOT NULL,
    "type"   "text",
    "munge"  "text",
    "access" "text",
    "index"  text[] DEFAULT '{}',
    PRIMARY KEY ("oid")
);

COMMIT;
