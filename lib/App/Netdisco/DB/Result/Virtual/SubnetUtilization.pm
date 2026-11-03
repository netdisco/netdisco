package App::Netdisco::DB::Result::Virtual::SubnetUtilization;

use strict;
use warnings;

use utf8;
use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('cidr_ips');
__PACKAGE__->result_source_instance->is_virtual(1);
# The join is on containment alone, as before domains, so that the planner
# keeps its parallel nested loop: as a join key the domain equality brought a
# single-threaded merge join over every node_ip row. OFFSET 0 holds the
# comparison above the join. DISTINCT, not OFFSET 0, keeps each subnet's
# domain computed once per row, because an OFFSET 0 subquery cannot sit
# under a parallel join.
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
  SELECT net as subnet,
         ld.name as vrf,
         power(2, (CASE family(net) WHEN 4 THEN 32 ELSE 128 END) - masklen(net)) as subnet_size,
         count(DISTINCT ip) as active,
         round(100 * count(DISTINCT ip) / power(2, (CASE family(net) WHEN 4 THEN 32 ELSE 128 END) - masklen(net))) as percent
    FROM (
      SELECT DISTINCT pairs.domain, pairs.net, pairs.ip
        FROM (
          SELECT s1.domain, s1.net, ni.ip,
                 CASE WHEN ni.vrf = '' THEN 0 ELSE l3_domain_of(ni.router_last, ni.vrf) END AS ip_domain
            FROM (SELECT DISTINCT s.net, s.last_discover,
                         CASE WHEN s.vrf = '' THEN 0 ELSE l3_domain_of(s.router_last, s.vrf) END AS domain
                    FROM subnets s) s1,
                 node_ip ni
            WHERE s1.net <<= ?::cidr
                  AND ni.ip <<= s1.net
                  AND ((
                    ni.time_first IS null
                    AND ni.time_last IS null
                  ) OR (
                    ni.time_last >= ?
                    AND ni.time_last <= ?
                  ))
                  AND s1.last_discover >= ?
          OFFSET 0) pairs
        WHERE pairs.ip_domain = pairs.domain
      UNION
      SELECT DISTINCT pairs.domain, pairs.net, pairs.ip
        FROM (
          SELECT s2.domain, s2.net, di.alias as ip,
                 CASE WHEN di.vrf = '' THEN 0 ELSE l3_domain_of(di.ip, di.vrf) END AS ip_domain
            FROM (SELECT DISTINCT s.net, s.last_discover,
                         CASE WHEN s.vrf = '' THEN 0 ELSE l3_domain_of(s.router_last, s.vrf) END AS domain
                    FROM subnets s) s2,
                 device_ip di JOIN device d USING (ip)
            WHERE s2.net <<= ?::cidr
                  AND di.alias <<= s2.net
                  AND s2.last_discover >= ?
                  AND d.last_discover >= ?
          OFFSET 0) pairs
        WHERE pairs.ip_domain = pairs.domain
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
