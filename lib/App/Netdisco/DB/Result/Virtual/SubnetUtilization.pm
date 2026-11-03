package App::Netdisco::DB::Result::Virtual::SubnetUtilization;

use strict;
use warnings;

use utf8;
use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('cidr_ips');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
  SELECT net as subnet,
         ld.name as vrf,
         power(2, (CASE family(net) WHEN 4 THEN 32 ELSE 128 END) - masklen(net)) as subnet_size,
         count(DISTINCT ip) as active,
         round(100 * count(DISTINCT ip) / power(2, (CASE family(net) WHEN 4 THEN 32 ELSE 128 END) - masklen(net))) as percent
    FROM (
      SELECT DISTINCT CASE WHEN s1.vrf = '' THEN 0 ELSE l3_domain_of(s1.router_last, s1.vrf) END AS domain,
             net, ni.ip
        FROM subnets s1, node_ip ni
        WHERE s1.net <<= ?::cidr
              AND ni.ip <<= s1.net
              AND CASE WHEN ni.vrf = '' THEN 0 ELSE l3_domain_of(ni.router_last, ni.vrf) END
                = CASE WHEN s1.vrf = '' THEN 0 ELSE l3_domain_of(s1.router_last, s1.vrf) END
              AND ((
                ni.time_first IS null
                AND ni.time_last IS null
              ) OR (
                ni.time_last >= ?
                AND ni.time_last <= ?
              ))
              AND s1.last_discover >= ?
      UNION
      SELECT DISTINCT CASE WHEN s2.vrf = '' THEN 0 ELSE l3_domain_of(s2.router_last, s2.vrf) END AS domain,
             net, di.alias as ip
        FROM subnets s2, device_ip di JOIN device d USING (ip)
        WHERE s2.net <<= ?::cidr
              AND di.alias <<= s2.net
              AND CASE WHEN di.vrf = '' THEN 0 ELSE l3_domain_of(di.ip, di.vrf) END
                = CASE WHEN s2.vrf = '' THEN 0 ELSE l3_domain_of(s2.router_last, s2.vrf) END
              AND s2.last_discover >= ?
              AND d.last_discover >= ?
    ) as joined
    JOIN l3_domain ld ON ld.id = joined.domain
    GROUP BY joined.domain, net, ld.name
    ORDER BY percent ASC
ENDSQL

__PACKAGE__->add_columns(
  "subnet",
  { data_type => "cidr", is_nullable => 0 },
  "vrf",
  { data_type => "text", is_nullable => 0 },
  "subnet_size",
  { data_type => "integer", is_nullable => 0 },
  "active",
  { data_type => "integer", is_nullable => 0 },
  "percent",
  { data_type => "integer", is_nullable => 0 },
);

1;
