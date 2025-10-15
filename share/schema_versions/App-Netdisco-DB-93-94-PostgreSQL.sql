BEGIN;

CREATE TABLE portctl_role (
    "id" SERIAL PRIMARY KEY,
    "role_name" text NOT NULL,
    "device_acl_id" integer NOT NULL,
    "port_acl_id" integer NOT NULL
);

CREATE TABLE access_control_list (
    "id" SERIAL PRIMARY KEY,
    "acl_name" text,
    "rules" text[] NOT NULL DEFAULT '{}'
);

COMMIT;
