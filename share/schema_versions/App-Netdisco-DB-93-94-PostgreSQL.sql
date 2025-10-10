BEGIN;

CREATE TABLE portctl_role (
    "name" text PRIMARY KEY,
    "device_acl_id" integer NOT NULL,
    "port_acl_id" integer NOT NULL
);

CREATE TABLE access_control_list (
    "id" SERIAL PRIMARY KEY,
    "name" text,
    "rules" text[] NOT NULL DEFAULT '{}'
);

COMMIT;
