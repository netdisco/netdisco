BEGIN;

alter table node_ip add column custom_fields jsonb NULL DEFAULT '{}'::jsonb;

CREATE INDEX idx_node_ip_custom_fields ON node_ip USING gin (custom_fields);

COMMIT;
