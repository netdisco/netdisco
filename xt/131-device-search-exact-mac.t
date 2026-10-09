#!/usr/bin/env perl

# Checks how Device search_fuzzy matches a MAC address: a valid MAC is compared
# with equality, which the port MAC index serves, and partial or wildcard input
# keeps its substring match. These assert the generated SQL, so they need no
# database.

use strict;
use warnings;

use Test::More 0.88;
use App::Netdisco::DB;

my $schema = do {
  local $SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /unversioned/ };
  my $s = App::Netdisco::DB->clone;
  $s->storage_type('::DBI::Pg');
  $s->connection('dbi:Pg:dbname=netdisco_xt_offline;host=127.0.0.1;port=1');
  $s;
};

sub fuzzy_sql {
  my ($sql, @bind) = @{ ${ $schema->resultset('Device')->search_fuzzy(shift)->as_query } };
  return ($sql, [ map { ref $_ ? $_->[1] : $_ } @bind ]);
}

subtest 'search_fuzzy__valid_mac__compares_with_equality' => sub {
  my ($sql, $bind) = fuzzy_sql('04bd.88cd.937c');
  like($sql, qr/ports_by_exact_mac\.mac = \?/, 'ports joined on MAC equality');
  unlike($sql, qr/mac::text ILIKE/i, 'no text match on any MAC column');
  is(scalar(grep { defined && $_ eq '04:bd:88:cd:93:7c' } @$bind), 3,
    'the IEEE form is bound for the join and both comparisons');
};

subtest 'search_fuzzy__partial_mac__keeps_ilike' => sub {
  my ($sql) = fuzzy_sql('04:bd');
  like($sql, qr/ports_by_mac\.mac::text ILIKE/i, 'partial input keeps the substring match');
  unlike($sql, qr/ports_by_exact_mac/, 'and does not use the equality join');
};

done_testing;
