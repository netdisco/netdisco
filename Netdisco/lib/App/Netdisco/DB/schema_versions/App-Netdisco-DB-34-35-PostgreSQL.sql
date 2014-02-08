BEGIN;

CREATE INDEX node_ip_idx_ip_active ON node_ip (ip, active);

COMMIT;
