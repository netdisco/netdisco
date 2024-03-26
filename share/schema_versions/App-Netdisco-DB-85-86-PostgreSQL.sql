BEGIN;

alter table node_ip add seen_on_router_first jsonb NULL DEFAULT '{}'::jsonb;
alter table node_ip add seen_on_router_last jsonb NULL DEFAULT '{}'::jsonb;

CREATE INDEX idx_node_ip_seen_on_router_first ON node_ip USING gin (seen_on_router_first);
CREATE INDEX idx_node_ip_seen_on_router_last  ON node_ip USING gin (seen_on_router_last);

COMMIT;
