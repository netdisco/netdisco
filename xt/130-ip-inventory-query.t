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

my $rs = eval {
  $schema->resultset('DeviceIp')->ip_inventory(NetAddr::IP::Lite->new('10.0.0.0/24'), {
    never => 1, age_invert => 0, limit => 256,
    start => '1970-01-01 00:00:00', end => '2030-12-31 23:59:59',
  });
};
ok($rs, 'ip_inventory builds a resultset') or BAIL_OUT("ip_inventory: $@");
my ($sql) = @{ ${ $rs->as_query } };

subtest 'ip_inventory__branches__are_joined_with_union_all' => sub {
  my $all = () = $sql =~ /\bUNION ALL\b/g;
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
  like($sql, qr/DISTINCT ON \(ip\)/, 'one row per IP');
  like($sql, qr/ORDER BY ip ASC, CASE WHEN active AND NOT node THEN 0 WHEN active THEN 1 WHEN node THEN 2 ELSE 3 END, time_last DESC NULLS LAST, dns ASC, mac ASC/,
    'active device row, active node, inactive node, generated; then most recently seen, name, MAC');
};

subtest 'ip_inventory__age_invert__keeps_rows_outside_the_range' => sub {
  my $inverted = $schema->resultset('DeviceIp')->ip_inventory(NetAddr::IP::Lite->new('10.0.0.0/24'), {
    age_invert => 1, start => '2020-01-01 00:00:00', end => '2020-02-01 23:59:59' });
  my ($inverted_sql) = @{ ${ $inverted->as_query } };
  like($inverted_sql, qr/time_last < \? OR time_last > \?/, 'seen before the start or after the end');
};

done_testing;
