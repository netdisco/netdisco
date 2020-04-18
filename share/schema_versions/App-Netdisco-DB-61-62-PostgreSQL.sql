BEGIN;

ALTER TABLE device RENAME COLUMN ports TO num_ports;

COMMIT;
