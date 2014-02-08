BEGIN;

-- Database Schema Modifications for upgrading from 0.9x to 0.93

ALTER TABLE device_port ADD COLUMN remote_type text;
ALTER TABLE device_port ADD COLUMN remote_id   text;
ALTER TABLE device_port ADD COLUMN vlan        text;

ALTER TABLE device      ADD COLUMN vtp_domain  text;

ALTER TABLE users       ADD COLUMN fullname    text;
ALTER TABLE users       ADD COLUMN note        text;

COMMIT;
