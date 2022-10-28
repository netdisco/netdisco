BEGIN;

ALTER TABLE device ADD COLUMN "pae_is_enabled" boolean;

ALTER TABLE device_port_properties ADD COLUMN "pae_authconfig_state" text;
ALTER TABLE device_port_properties ADD COLUMN "pae_authconfig_port_control" text;
ALTER TABLE device_port_properties ADD COLUMN "pae_authconfig_port_status" text;
ALTER TABLE device_port_properties ADD COLUMN "pae_authsess_user" text;
ALTER TABLE device_port_properties ADD COLUMN "pae_authsess_mab" text;
ALTER TABLE device_port_properties ADD COLUMN "pae_last_eapol_frame_source" text;
ALTER TABLE device_port_properties ADD COLUMN "pae_is_authenticator" boolean;
ALTER TABLE device_port_properties ADD COLUMN "pae_is_supplicant" boolean;

COMMIT;
