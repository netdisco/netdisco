BEGIN;

CREATE INDEX idx_device_custom_fields ON device USING gin (custom_fields);
CREATE INDEX idx_device_port_custom_fields ON device_port USING gin (custom_fields);

COMMIT;
