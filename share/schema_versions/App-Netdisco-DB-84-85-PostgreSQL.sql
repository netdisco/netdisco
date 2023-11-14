BEGIN;

ALTER TABLE node ALTER COLUMN oui TYPE varchar(9);

CREATE TABLE manufacturer (
    "company"  text NOT NULL,
    "abbrev"   text NOT NULL,
    "base"     text NOT NULL,
    "bits"     integer NOT NULL,
    "first"    macaddr NOT NULL,
    "last"     macaddr NOT NULL,
    "range"    int8range NOT NULL,
    PRIMARY KEY ("base"),
    EXCLUDE USING GIST (range WITH &&)
);

CREATE INDEX idx_manufacturer_first_last ON manufacturer ("first", "last" DESC);

COMMIT;
