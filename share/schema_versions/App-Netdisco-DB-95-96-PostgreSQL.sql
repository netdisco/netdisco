BEGIN;

ALTER TABLE node_ip ADD CONSTRAINT node_ip_pkey PRIMARY KEY (mac, ip, vrf);

COMMIT;
