#!/usr/bin/env perl

# Checks the SQL that DeviceIp's ip_inventory builds for the IP Inventory
# report: its branches are joined without deduplication, the vendor lookup runs
# only on the rows returned, and DISTINCT ON keeps the right row per IP. These
# assert the generated SQL, so they need no database.

use strict;
use warnings;

use Test::More 0.88;
use NetAddr::IP::Lite;
use App::Netdisco::DB;

my $schema = do {
  local $SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /unversioned/ };
  my $s = App::Netdisco::DB->clone;
  $s->storage_type('::DBI::Pg');
  $s->connection('dbi:Pg:dbname=netdisco_xt_offline;host=127.0.0.1;port=1');
  $s;
};

# the never branch asks the database whether a named-VRF subnet overlaps the
# prefix; there is no database here, so the answer is set per case
our $named_overlap = 1;
{
  no warnings 'redefine';
  *App::Netdisco::DB::ResultSet::DeviceIp::_named_vrf_subnet_overlaps = sub { $named_overlap };
}

sub never_sql {
  my $rs = eval {
    $schema->resultset('DeviceIp')->ip_inventory(NetAddr::IP::Lite->new('10.0.0.0/24'), {
      never => 1, age_invert => 0, limit => 256,
      start => '1970-01-01 00:00:00', end => '2030-12-31 23:59:59',
    });
  };
  ok($rs, 'ip_inventory builds a resultset') or BAIL_OUT("ip_inventory: $@");
  return ${ $rs->as_query }->[0];
}

my $sql = never_sql();
my $default_sql = do { local $named_overlap = 0; never_sql() };

subtest 'ip_inventory__branches__are_joined_with_union_all' => sub {
  # the never-seen branch has a UNION ALL of its own inside it
  (my $branches = $sql) =~ s/WITH addr AS \(.*?\) AS o\b//s;
  my $all = () = $branches =~ /\bUNION ALL\b/g;
  is($all, 3, 'device, node_ip, node_nbt and never-seen branches joined by three UNION ALL');
  unlike($sql, qr/\bUNION\b(?!\s+ALL)/, 'no deduplicating UNION');
};

subtest 'ip_inventory__node_branches__do_not_join_manufacturer' => sub {
  unlike($sql, qr/JOIN\s+manufacturer/i, 'no branch joins manufacturer');
};

subtest 'ip_inventory__vendor__is_looked_up_after_the_limit' => sub {
  my $at = index($sql, ' FROM (');
  ok($at > 0, 'the outer query selects from a subquery');
  my ($outer, $inner) = (substr($sql, 0, $at), substr($sql, $at));
  like($outer, qr/FROM manufacturer m/, 'the vendor lookup is in the outer select list');
  unlike($inner, qr/manufacturer/, 'and nowhere below it');
  like($inner, qr/LIMIT \?/, 'the limit is applied below the vendor lookup');
};

subtest 'ip_inventory__distinct_on__ranks_real_rows_above_generated_then_recency' => sub {
  # a generated never-seen row (active and node both false) must lose to any
  # real binding, even an inactive one, or a seen address reads as never seen
  like($sql, qr/DISTINCT ON \(ip, domain\)/, 'one row per IP in each L3 domain');
  like($sql, qr/ORDER BY ip ASC, domain ASC, CASE WHEN active AND NOT node THEN 0 WHEN active THEN 1 WHEN node THEN 2 ELSE 3 END, time_last DESC NULLS LAST, dns ASC, mac ASC/,
    'active device row, active node, inactive node, generated; then most recently seen, name, MAC');
};

# Generated never-seen rows take the L3 domain of each stored subnet holding
# them, so a subnet stored only in a VRF is not shown again in the default
# domain. Rows are checked against PostgreSQL outside CI; here, the SQL shape.
my ($never_sql) = $sql =~ /(WITH addr AS \(.*?\) AS o\b)/s;

subtest 'ip_inventory__never_in_vrf_only_subnet__rows_take_the_subnet_domain' => sub {
  ok(defined $never_sql, 'found the never-seen branch');
  like($never_sql // '', qr/cand AS \(\s*SELECT DISTINCT\s+GREATEST\(network\(s\.net\) - network\(a\.prefix\), 1\) AS lo,\s+LEAST\(broadcast\(s\.net\) - network\(a\.prefix\), broadcast\(a\.prefix\) - network\(a\.prefix\) - 1\) AS hi,\s+CASE WHEN s\.vrf = '' THEN 0 ELSE l3_domain_of\(s\.router_last, s\.vrf\) END AS domain\s+FROM subnets s, addr a\s+WHERE s\.net && a\.prefix\s+\)/,
    'each overlapping subnet, as host offsets, in the domain of the router that reported it');
  like($never_sql // '', qr/SELECT host\(network\(a\.prefix\) \+ o\.int\)::inet AS ip,.*\bo\.domain\s+FROM addr a, \(/s,
    'a generated address carries the domain it was generated in');
};

subtest 'ip_inventory__never_outside_any_stored_subnet__rows_in_default_domain' => sub {
  like($never_sql // '', qr/SELECT g\.int, 0 FROM addr, generate_series\(1, \(broadcast\(prefix\) - network\(prefix\) - 1\)\) AS g\(int\)\s+WHERE NOT EXISTS \(SELECT 1 FROM held h WHERE h\.int = g\.int\)/,
    'an address no resolving subnet holds is domain 0');
};

subtest 'ip_inventory__never_in_subnet_stored_in_two_domains__one_row_per_domain' => sub {
  # a NULL domain (ambiguous name) holds nothing, so it adds no default row
  # beside a subnet that does resolve
  like($never_sql // '', qr/held AS \(\s*SELECT DISTINCT generate_series\(lo, hi\) AS int, domain\s+FROM cand\s+WHERE domain IS NOT NULL\s+\)/,
    'one row per address in each resolving domain');
  unlike($never_sql // '', qr/\bLIMIT\b|\bGROUP BY\b/, 'no domain is dropped in favor of another');
};

subtest 'ip_inventory__never_switch_off__unchanged' => sub {
  # with every vrf '' every held offset is domain 0 and the rest are added as
  # 0, so the rows are today's; compared row for row on PostgreSQL
  like($never_sql // '', qr/CASE WHEN s\.vrf = '' THEN 0 ELSE /, 'a default-table subnet is domain 0 without a lookup');
  my $bound = () = $sql =~ /\?::inet/g;
  is($bound, 1, 'the queried prefix is bound once');
  unlike($never_sql // '', qr/>>=|<<=/, 'no per-address containment test against each subnet');
};

subtest 'ip_inventory__never_no_named_subnet_overlaps__uses_default_only_form' => sub {
  # switch-off sites and VRF-free prefixes keep the plan they had before domains
  like($default_sql, qr/generate_series\(1, \(broadcast\(prefix\) - network\(prefix\) - 1\)\) AS int\s+FROM \(\s+SELECT \?::inet AS prefix\s+\) AS addr\s+\) AS sub/,
    'addresses generated straight from the prefix');
  like($default_sql, qr/\b0 AS domain\b.*\b0 AS domain\b/s, 'NetBIOS and never-seen rows both domain 0');
  unlike($default_sql, qr/WITH addr AS|FROM subnets\b/, 'no stored subnet is read');
  my $all = () = $default_sql =~ /\bUNION ALL\b/g;
  is($all, 3, 'still four branches');
};

subtest 'ip_inventory__age_invert__keeps_rows_outside_the_range' => sub {
  my $inverted = $schema->resultset('DeviceIp')->ip_inventory(NetAddr::IP::Lite->new('10.0.0.0/24'), {
    age_invert => 1, start => '2020-01-01 00:00:00', end => '2020-02-01 23:59:59' });
  my ($inverted_sql) = @{ ${ $inverted->as_query } };
  like($inverted_sql, qr/time_last < \? OR time_last > \?/, 'seen before the start or after the end');
};

done_testing;
