BEGIN;

CREATE TABLE portctl_role (
    role_name text PRIMARY KEY
);

CREATE TABLE portctl_role_device (
    role_name       text NOT NULL,
    device_ip  inet NOT NULL,
    can_admin  boolean NOT NULL DEFAULT true,
    PRIMARY KEY (role_name, device_ip)
);

CREATE TABLE portctl_role_device_port (
    role_name       text NOT NULL,
    device_ip  inet NOT NULL,
    acl       text NOT NULL,
    PRIMARY KEY (role_name, device_ip, acl)
);

CREATE INDEX idx_role_device_port ON portctl_role_device_port(role_name, device_ip, acl);

COMMIT;
