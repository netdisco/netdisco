BEGIN;

SET LOCAL client_min_messages = warning;

DROP INDEX IF EXISTS device_ip_idx_ip;
DROP INDEX IF EXISTS device_ip_idx_ip_port;
DROP INDEX IF EXISTS device_port_idx_ip;
DROP INDEX IF EXISTS device_port_idx_remote_ip;
DROP INDEX IF EXISTS device_port_vlan_idx_ip;
DROP INDEX IF EXISTS device_port_vlan_idx_ip_port;
DROP INDEX IF EXISTS device_port_vlan_idx_ip_vlan;
DROP INDEX IF EXISTS device_vlan_idx_ip;
DROP INDEX IF EXISTS node_idx_oui;
DROP INDEX IF EXISTS node_idx_switch;
DROP INDEX IF EXISTS node_idx_switch_port;

CREATE INDEX IF NOT EXISTS idx_admin_action ON admin USING btree (action);
CREATE INDEX IF NOT EXISTS idx_admin_entered ON admin USING btree (entered);
CREATE INDEX IF NOT EXISTS idx_admin_status ON admin USING btree (status);
CREATE INDEX IF NOT EXISTS idx_device_dns ON device USING btree (dns);
CREATE INDEX IF NOT EXISTS idx_device_ip_alias ON device_ip USING btree (alias);
CREATE INDEX IF NOT EXISTS idx_device_ip_ip_port ON device_ip USING btree (ip, port);
CREATE INDEX IF NOT EXISTS idx_device_layers ON device USING btree (layers);
CREATE INDEX IF NOT EXISTS idx_device_model ON device USING btree (model);
CREATE INDEX IF NOT EXISTS idx_device_port_ip_port_duplex ON device_port USING btree (ip, port, duplex);
CREATE INDEX IF NOT EXISTS idx_device_port_ip_up_admin ON device_port USING btree (ip, up_admin);
CREATE INDEX IF NOT EXISTS idx_device_port_log_1 ON device_port_log USING btree (ip, port);
CREATE INDEX IF NOT EXISTS idx_device_port_log_user ON device_port_log USING btree (username);
CREATE INDEX IF NOT EXISTS idx_device_port_mac ON device_port USING btree (mac);
CREATE INDEX IF NOT EXISTS idx_device_port_remote_ip ON device_port USING btree (remote_ip);
CREATE INDEX IF NOT EXISTS idx_device_port_ssid_ip_port ON device_port_ssid USING btree (ip, port);
CREATE INDEX IF NOT EXISTS idx_device_vendor ON device USING btree (vendor);
CREATE INDEX IF NOT EXISTS idx_node_ip_ip_active ON node_ip USING btree (ip, active);
CREATE INDEX IF NOT EXISTS idx_node_ip_mac_active ON node_ip USING btree (mac, active);
CREATE INDEX IF NOT EXISTS idx_node_mac_active ON node USING btree (mac, active);
CREATE INDEX IF NOT EXISTS idx_node_nbt_domain ON node_nbt USING btree (domain);
CREATE INDEX IF NOT EXISTS idx_node_nbt_mac_active ON node_nbt USING btree (mac, active);
CREATE INDEX IF NOT EXISTS idx_node_nbt_nbname ON node_nbt USING btree (nbname);
CREATE INDEX IF NOT EXISTS idx_node_switch_port_active ON node USING btree (switch, port, active);

DELETE FROM device_port_ssid WHERE ip IS NULL OR port IS NULL OR bssid IS NULL;

DELETE FROM device_port_ssid a USING device_port_ssid b
  WHERE a.ip = b.ip AND a.port = b.port AND a.bssid = b.bssid AND a.ctid < b.ctid;

ALTER TABLE device_port_ssid ALTER COLUMN ip SET NOT NULL;
ALTER TABLE device_port_ssid ALTER COLUMN port SET NOT NULL;
ALTER TABLE device_port_ssid ALTER COLUMN bssid SET NOT NULL;
ALTER TABLE device_port_ssid DROP CONSTRAINT IF EXISTS device_port_ssid_pkey;
ALTER TABLE device_port_ssid ADD CONSTRAINT device_port_ssid_pkey PRIMARY KEY (ip, bssid, port);

SET LOCAL client_min_messages = notice;

DO $$
BEGIN
  IF to_regclass('device_route') IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM device_route) THEN
      RAISE NOTICE 'device_route kept: it holds rows';
    ELSE
      DROP TABLE device_route;
    END IF;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'community' AND column_name = 'snmp_auth_tag') THEN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'community' AND column_name = 'snmp_auth_tag_read') THEN
      RAISE NOTICE 'community.snmp_auth_tag kept: community has no snmp_auth_tag_read';
    ELSIF EXISTS (SELECT 1 FROM community WHERE snmp_auth_tag IS NOT NULL) THEN
      RAISE NOTICE 'community.snmp_auth_tag kept: it holds values';
    ELSE
      ALTER TABLE community DROP COLUMN snmp_auth_tag;
    END IF;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = current_schema() AND table_name = 'portctl_role') THEN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = current_schema() AND table_name = 'access_control_list_map') THEN
      RAISE NOTICE 'portctl_role kept: there is no access_control_list_map';
    ELSIF EXISTS (SELECT 1 FROM portctl_role) THEN
      RAISE NOTICE 'portctl_role kept: it holds rows';
    ELSE
      DROP TABLE portctl_role;
    END IF;
  END IF;
END $$;

SET LOCAL client_min_messages = warning;

CREATE TABLE IF NOT EXISTS schema_step_forced (
  step integer NOT NULL,
  forced_at timestamp NOT NULL DEFAULT LOCALTIMESTAMP,
  failed_count integer NOT NULL,
  failures jsonb NOT NULL DEFAULT '[]'
);

CREATE OR REPLACE FUNCTION port_sortkey(raw text)
  RETURNS text LANGUAGE sql IMMUTABLE STRICT AS $$
    WITH norm AS (
      SELECT regexp_replace(btrim(raw, ' '), '^10(GigabitEthernet)', '\1') AS s
    ), chunks AS (
      SELECT m[1] AS chunk, ord
        FROM norm, LATERAL regexp_matches(norm.s, '([0-9]+|[^0-9]+)', 'g')
               WITH ORDINALITY AS t(m, ord)
       WHERE norm.s !~* '^0x[0-9a-f]+$'
    ), tokens AS (
      SELECT string_agg(
               CASE
                 WHEN chunk ~ '^[[:space:]]+$' THEN 'A' || chunk
                 WHEN chunk ~ '^0'             THEN 'A' || chunk
                 WHEN chunk ~ '^[0-9]'         THEN 'B' || lpad(length(chunk)::text, 3, '0') || chunk
                 ELSE                               'C' || chunk
               END || E'\x01', '' ORDER BY ord) AS body
        FROM chunks
    )
    SELECT CASE WHEN norm.s ~* '^0x[0-9a-f]+$'
                THEN 'A' || norm.s || E'\x01'
                ELSE COALESCE(tokens.body, '')
           END || E'A0\x01'
      FROM norm, tokens
  $$;

COMMIT;
