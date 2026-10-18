BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'device' AND column_name = 'is_pseudo') THEN
    ALTER TABLE device ADD COLUMN "is_pseudo" boolean DEFAULT false;

    UPDATE device SET is_pseudo = false;

    UPDATE device SET is_pseudo = true WHERE vendor = 'netdisco';

    UPDATE device SET model = 'pseudodevice' WHERE vendor = 'netdisco';

    UPDATE device SET os_ver = '2.51.0' WHERE vendor = 'netdisco' AND os_ver IS NULL;

    UPDATE device SET os = 'netdisco' WHERE vendor = 'netdisco' AND os IS NULL;
  END IF;
END
$$;

COMMIT;
