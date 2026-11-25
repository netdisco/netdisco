BEGIN;

SET LOCAL client_min_messages = warning;

CREATE INDEX IF NOT EXISTS idx_node_ip_ip_spgist ON node_ip USING spgist (ip inet_ops);

CREATE INDEX IF NOT EXISTS idx_device_ip_alias_spgist ON device_ip USING spgist (alias inet_ops);

COMMIT;
