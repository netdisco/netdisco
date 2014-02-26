package App::Netdisco::DB::Result::Virtual::SubnetUtilization;

use strict;
use warnings;

use utf8;
use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('subnet_utilization');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
  SELECT net as subnet,
         @@ iprange(net) as subnet_size,
         count(DISTINCT ip) as active,
         round(100 * count(DISTINCT ip) / @@ iprange(net)) as percent
    FROM (
      SELECT DISTINCT net, ni.ip
        FROM subnets s1, node_ip ni
        WHERE iprange(s1.net) <<= ?::iprange
              AND iprange(ni.ip::cidr) <<= iprange(s1.net)
              AND ni.time_last > (now() - ?::interval)
              AND s1.last_discover > (now() - ?::interval)
      UNION
      SELECT DISTINCT net, di.alias as ip
        FROM subnets s2, device_ip di JOIN device d USING (ip)
        WHERE iprange(s2.net) <<= ?::iprange
              AND iprange(di.alias::cidr) <<= iprange(s2.net)
              AND s2.last_discover > (now() - ?::interval)
              AND d.last_discover > (now() - ?::interval)
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
