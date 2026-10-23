BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'community' AND column_name IN ('snmp_auth_tag', 'snmp_auth_tag_read')) THEN
    ALTER TABLE community ADD COLUMN snmp_auth_tag text;
  END IF;
END
$$;

COMMIT;
