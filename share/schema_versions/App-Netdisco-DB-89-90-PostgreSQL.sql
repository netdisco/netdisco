BEGIN;

CREATE TABLE product (
    "oid"    "text" NOT NULL,
    "mib"    "text" NOT NULL,
    "leaf"   "text" NOT NULL,
    "descr"  "text",
    PRIMARY KEY ("oid")
);

COMMIT;
