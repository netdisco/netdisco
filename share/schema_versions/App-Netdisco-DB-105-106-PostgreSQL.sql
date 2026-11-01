BEGIN;

SET LOCAL client_min_messages = warning;

CREATE TABLE IF NOT EXISTS config_version (
  scope   text   PRIMARY KEY,
  version bigint NOT NULL DEFAULT 0
);
INSERT INTO config_version (scope, version) VALUES ('acl', 0)
  ON CONFLICT (scope) DO NOTHING;

COMMIT;
