BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = current_schema() AND table_name IN ('portctl_role', 'access_control_list_map')) THEN
    CREATE TABLE portctl_role (
        "id" SERIAL PRIMARY KEY,
        "role_name" text NOT NULL,
        "device_acl_id" integer NOT NULL,
        "port_acl_id" integer NOT NULL
    );
  END IF;
END
$$;

CREATE TABLE access_control_list (
    "id" SERIAL PRIMARY KEY,
    "acl_name" text,
    "rules" text[] NOT NULL DEFAULT '{}'
);

COMMIT;
