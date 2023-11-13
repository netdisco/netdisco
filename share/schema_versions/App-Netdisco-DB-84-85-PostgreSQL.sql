BEGIN;

CREATE TABLE manufacturer (
    "company"  text NOT NULL,
    "abbrev"   text NOT NULL,
    "base"     text NOT NULL,
    "bits"     integer NOT NULL,
    "first"    macaddr NOT NULL,
    "last"     macaddr NOT NULL,
    "range"    int8range NOT NULL,
    "oui"      varchar(8) NOT NULL,
    PRIMARY KEY ("base"),
    EXCLUDE USING GIST (range WITH &&)
);

CREATE INDEX idx_manufacturer_first ON manufacturer ("first");

CREATE INDEX idx_manufacturer_last  ON manufacturer ("last");

COMMIT;
