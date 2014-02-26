BEGIN;

CREATE INDEX idx_subnets_net ON subnets USING gist (iprange(net));
CREATE INDEX idx_node_ip_ip  ON node_ip USING gist (iprange(ip::cidr));
CREATE INDEX idx_device_ip_alias ON device_ip USING gist (iprange(alias::cidr));
  
COMMIT;
