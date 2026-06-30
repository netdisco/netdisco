BEGIN;

ALTER TABLE access_control_list DROP COLUMN acl_name;

ALTER TABLE portctl_role RENAME TO access_control_list_map;

ALTER SEQUENCE portctl_role_id_seq RENAME TO access_control_list_map_id_seq;

ALTER TABLE access_control_list_map RENAME CONSTRAINT portctl_role_pkey TO access_control_list_map_pkey;

ALTER TABLE access_control_list_map RENAME COLUMN role_name TO acl_name;

ALTER TABLE access_control_list_map RENAME COLUMN device_acl_id TO left_acl_id;

ALTER TABLE access_control_list_map RENAME COLUMN port_acl_id TO right_acl_id;

CREATE TABLE access_control_list_name (
    "acl_name" text PRIMARY KEY,
    "acl_type" text NOT NULL CHECK (acl_type IN ('host', 'host_host', 'host_port'))
);

INSERT INTO access_control_list_name (acl_name, acl_type) SELECT DISTINCT acl_name, 'host_port' FROM access_control_list_map;

COMMIT;
