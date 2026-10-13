#!/usr/bin/env perl

# Checks how Device searches select a device by address: ip IN (its own address
# UNION its aliases), each half served by an index. The device half matters
# because some devices have no device_ip row for their own address. These
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

my $IN_UNION = qr/me\.ip IN \(\s*SELECT ip FROM device WHERE ip <<= \? UNION SELECT ip FROM device_ip WHERE alias <<= \?\s*\)/;

sub sql_of { return ${ $_[0]->as_query }->[0] }

subtest 'search_aliases__ip__uses_in_over_union_without_join' => sub {
  my $sql = sql_of(scalar $schema->resultset('Device')->search_aliases('10.0.0.1'));
  like($sql, $IN_UNION, 'own address or alias, both index-served');
  unlike($sql, qr/device_ips/, 'no join to device_ip');
};

subtest 'search_by_field__ip__uses_in_over_union' => sub {
  my $sql = sql_of(scalar $schema->resultset('Device')->search_by_field({ ip => NetAddr::IP::Lite->new('10.0.0.0/24') }));
  like($sql, $IN_UNION, 'own address or alias, both index-served');
  unlike($sql, qr/device_ips/, 'an ip parameter alone adds no join');
};

subtest 'search_fuzzy__ip__uses_in_over_union' => sub {
  my $sql = sql_of(scalar $schema->resultset('Device')->search_fuzzy('10.0.0.1'));
  like($sql, $IN_UNION, 'own address or alias, both index-served');
  # the join condition may test aliases per device; the WHERE clause must not
  my ($where) = $sql =~ /\bWHERE\b(.*)\z/s;
  unlike($where // '', qr/device_ips_by_address_or_name\.alias <<=/, 'no containment test across the join in WHERE');
};

subtest 'search_by_field__matchall_with_dns_and_ip__keeps_the_alias_row_test' => sub {
  # with "match all", the name and the subnet must match the same alias row,
  # which the IN form cannot express
  my $sql = sql_of(scalar $schema->resultset('Device')->search_by_field({
    matchall => 1, dns => 'foo', ip => NetAddr::IP::Lite->new('10.0.0.0/24') }));
  like($sql, qr/device_ips\.alias <<= \?/, 'the subnet is tested on the same joined alias row');
  unlike($sql, $IN_UNION, 'not through the independent IN form');
};

subtest 'search_aliases__name__keeps_device_ips_join' => sub {
  my $sql = sql_of(scalar $schema->resultset('Device')->search_aliases('core-switch'));
  like($sql, qr/device_ips\.dns ILIKE/i, 'names still match device_ip dns through the join');
};

done_testing;
