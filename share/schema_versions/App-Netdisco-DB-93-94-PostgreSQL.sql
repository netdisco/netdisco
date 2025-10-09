BEGIN;

CREATE TABLE portctl_role (
    "name" text PRIMARY KEY,
    "device_acl" integer NOT NULL,
    "port_acl" integer
);

CREATE TABLE access_control_list (
    "id" SERIAL PRIMARY KEY,
    "name" text,
    "rules" text[] NOT NULL
);

COMMIT;
