BEGIN;

ALTER TABLE device_port_properties ADD COLUMN "remote_is_wap" bool DEFAULT false;
ALTER TABLE device_port_properties ADD COLUMN "remote_is_phone" bool DEFAULT false;
ALTER TABLE device_port_properties ADD COLUMN "remote_vendor" text;
ALTER TABLE device_port_properties ADD COLUMN "remote_model"  text;
ALTER TABLE device_port_properties ADD COLUMN "remote_os_ver" text;
ALTER TABLE device_port_properties ADD COLUMN "remote_serial" text;

COMMIT;
