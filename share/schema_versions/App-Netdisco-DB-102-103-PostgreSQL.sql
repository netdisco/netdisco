BEGIN;

SET LOCAL client_min_messages = warning;

DROP INDEX IF EXISTS idx_node_ip_seen_on_router_first;
DROP INDEX IF EXISTS idx_node_ip_seen_on_router_last;

COMMIT;
