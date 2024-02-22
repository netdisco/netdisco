BEGIN;

alter table node_ip add column custom_fields jsonb NULL DEFAULT '{}'::jsonb;

COMMIT;
