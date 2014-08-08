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
         power(2, (32 - masklen(net))) as subnet_size,
         count(DISTINCT ip) as active,
         round(100 * count(DISTINCT ip) / (power(2, (32 - masklen(net))) - 2)) as percent
    FROM (
      SELECT DISTINCT net, ni.ip
        FROM subnets s1, node_ip ni
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
      UNION
      SELECT DISTINCT net, di.alias as ip
        FROM subnets s2, device_ip di JOIN device d USING (ip)
        WHERE s2.net <<= ?::cidr
              AND di.alias <<= s2.net
              AND s2.last_discover >= ?
              AND d.last_discover >= ?
    ) as joined
    GROUP BY net
    ORDER BY percent ASC
ENDSQL

__PACKAGE__->add_columns(
  "subnet",
  { data_type => "cidr", is_nullable => 0 },
  "subnet_size",
  { data_type => "integer", is_nullable => 0 },
  "active",
  { data_type => "integer", is_nullable => 0 },
  "percent",
  { data_type => "integer", is_nullable => 0 },
);

1;
