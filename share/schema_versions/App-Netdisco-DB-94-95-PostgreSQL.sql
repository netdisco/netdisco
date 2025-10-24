BEGIN;

ALTER TABLE node_ip ADD COLUMN vrf text DEFAULT '' NOT NULL;

ALTER TABLE node_ip DROP CONSTRAINT node_ip_pkey;

ALTER TABLE node_ip ADD CONSTRAINT node_ip_pkey PRIMARY KEY (mac, ip, vrf);

COMMIT;
