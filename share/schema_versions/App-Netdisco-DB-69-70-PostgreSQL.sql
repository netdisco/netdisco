BEGIN;

CREATE TABLE snmp_object (
    "oid"    "text" NOT NULL,
    "oid_parts" integer[] NOT NULL,
    "mib"    "text" NOT NULL,
    "leaf"   "text" NOT NULL,
    "type"   "text",
    "access" "text",
    "index"  text[] DEFAULT '{}',
    PRIMARY KEY ("oid")
);

CREATE INDEX idx_snmp_object_oid__pattern on snmp_object (oid text_pattern_ops);

COMMIT;
