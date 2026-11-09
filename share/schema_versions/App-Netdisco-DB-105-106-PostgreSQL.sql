BEGIN;

SET LOCAL client_min_messages = warning;

ALTER TABLE users ADD COLUMN IF NOT EXISTS portctl_roles text[];

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'users' AND column_name = 'portctl_role') THEN
    UPDATE users SET portctl_roles = ARRAY[portctl_role]
      WHERE portctl_role IS NOT NULL AND portctl_role <> '' AND portctl_roles IS NULL;
    ALTER TABLE users DROP COLUMN portctl_role;
  END IF;
END
$$;

COMMIT;
