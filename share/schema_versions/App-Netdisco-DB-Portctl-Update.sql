BEGIN;

CREATE TABLE portctl_role (
    role_name text PRIMARY KEY
)


CREATE TABLE portctl_role_device (
    role_name       text NOT NULL,
    device_ip  inet NOT NULL,
    PRIMARY KEY (role_name, device_ip),
);

-- Table for port-level permissions (unique id, plus role, device_ip, port)
CREATE TABLE portctl_role_device_port (
    role_name       text NOT NULL,
    device_ip  inet NOT NULL,
    port       text NOT NULL,
    can_admin  boolean NOT NULL DEFAULT true,
    PRIMARY KEY (role_name, device_ip, port)
);

CREATE INDEX idx_role_device_port ON role_device_port_permission(role, device_ip, port);


COMMIT;
