BEGIN;

CREATE TABLE portctl_role (
    "name" text NOT NULL,
    "device_acl_id" integer NOT NULL,
    "port_acl_id" integer NOT NULL,
    PRIMARY KEY("name", "device_acl_id", "port_acl_id") 
);

CREATE TABLE access_control_list (
    "id" SERIAL PRIMARY KEY,
    "name" text,
    "rules" text[] NOT NULL DEFAULT '{}'
);

COMMIT;
