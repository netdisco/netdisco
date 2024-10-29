BEGIN;

CREATE TABLE enterprise (
    "enterprise_number" integer NOT NULL,
    "organization"      text NOT NULL,
    PRIMARY KEY ("enterprise_number")
);

COMMIT;
