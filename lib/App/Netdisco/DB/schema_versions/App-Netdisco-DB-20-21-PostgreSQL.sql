BEGIN;

CREATE UNIQUE INDEX jobs_queued ON admin (
  action,
  coalesce(subaction, '_x_'),
  coalesce(device, '255.255.255.255'),
  coalesce(port, '_x_')
) WHERE status LIKE 'queued%';

COMMIT;
