#!/usr/bin/env perl

use strict;
use warnings;

# The evidence key decides which VRFs share an L3 domain: an L3 I-SID first,
# then identical route-target sets, then the bare name. A wrong precedence or
# an order-sensitive route-target key silently splits or merges customers, so
# these pin the SQL text. Only the database handle is faked, as in xt/187.

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use App::Netdisco;
use App::Netdisco::Util::L3Domain qw/l3_domain_evidence_sql recompute_l3_domains/;

my $sql = l3_domain_evidence_sql();
(my $flat = $sql) =~ s/\s+/ /g;

# each cleaned array is computed once per row, in a LATERAL fenced by OFFSET 0
# so the planner cannot inline it back into every use
my $cleaned = sub {
  my $column = shift;
  return quotemeta(qq{ARRAY(SELECT DISTINCT x COLLATE "C" FROM unnest($column) x WHERE x IS NOT NULL AND x <> '' ORDER BY x COLLATE "C")});
};

subtest 'evidence_key__isid_present__keyed_isid_before_rt' => sub {
  like($flat, qr/CASE WHEN d\.l3_isid IS NOT NULL THEN 'isid:' \|\| d\.l3_isid WHEN/, 'I-SID tested first');
  my $isid_at = index($flat, "'isid:'");
  my $rt_at   = index($flat, "'rt:'");
  ok($isid_at >= 0 && $rt_at > $isid_at, 'I-SID branch precedes the route-target branch');
};

subtest 'evidence_key__rt_arrays_unordered_with_duplicates__same_key' => sub {
  my ($imports, $exports) = ($cleaned->('d.rt_import'), $cleaned->('d.rt_export'));
  like($flat, qr/LATERAL \(SELECT $imports AS imp, $exports AS exp OFFSET 0\) s/, 'de-duplicated and sorted bytewise, once');
  like($flat, qr/array_to_string\(s\.imp, ','\) AS imports, array_to_string\(s\.exp, ','\) AS exports/, 'joined');
  like($flat, qr/SELECT 'rt:' \|\| t\.imports \|\| '\/' \|\| t\.exports AS rtkey OFFSET 0/, 'imports then exports');
  like($flat, qr/> 0 AS has_rt/, 'needs at least one non-empty set');
};

subtest 'evidence_key__rt_arrays_only_null_or_empty__falls_back_to_name' => sub {
  for my $column (qw/d.rt_import d.rt_export/) {
    like($flat, qr/@{[ $cleaned->($column) ]}/, "$column drops NULL and empty elements");
  }
  like($flat, qr/coalesce\(array_length\(s\.imp, 1\), 0\) \+ coalesce\(array_length\(s\.exp, 1\), 0\) > 0 AS has_rt/, 'has-route-targets test uses the filtered arrays');
  unlike($flat, qr/array_length\(d\.rt_(?:import|export), 1\)/, 'never counts the raw arrays');
};

subtest 'evidence_key__cleaned_arrays__computed_once_per_row' => sub {
  for my $column (qw/d.rt_import d.rt_export/) {
    my $count = () = $flat =~ m/@{[ $cleaned->($column) ]}/g;
    is($count, 1, "$column cleaned in one place");
  }
  my $fences = () = $flat =~ m/OFFSET 0\) \w/g;
  is($fences, 3, 'three LATERAL steps, each fenced');
};

subtest 'evidence_key__rt_set_over_200_bytes__md5_key' => sub {
  like($flat, qr/WHEN t\.has_rt THEN CASE WHEN octet_length\(k\.rtkey\) > 200 THEN 'rt:md5:' \|\| md5\(k\.rtkey\) ELSE k\.rtkey END/,
    'a long key is replaced by a digest of the full text');
  like($flat, qr/'same route targets import ' \|\| t\.imports \|\| ' export ' \|\| t\.exports/, 'the reason keeps the full sets');
};

subtest 'evidence_key__no_isid_no_rt__keyed_name' => sub {
  like($flat, qr/ELSE 'name:' \|\| d\.vrf END AS key/);
};

subtest 'reason__each_evidence__exact_text' => sub {
  like($flat, qr/'shared L3 I-SID ' \|\| d\.l3_isid/);
  like($flat, qr/WHEN t\.has_rt THEN 'same route targets import ' \|\| t\.imports \|\| ' export ' \|\| t\.exports/);
  like($flat, qr/ELSE 'same name ' \|\| d\.vrf END AS reason/);
};

subtest 'evidence__default_table__excluded_and_display_is_vrf' => sub {
  like($flat, qr/FROM device_vrf d CROSS JOIN LATERAL .* WHERE d\.vrf <> ''$/);
  like($flat, qr/d\.vrf AS display/);
  like($flat, qr/^SELECT d\.ip, d\.vrf,/, 'ip and vrf first');
};

my @ran;
package FakeDbh;
sub new { return bless {}, $_[0] }
sub do  { my ($self, $sql) = @_; push @ran, $sql; return '0E0' }
sub selectrow_array { my ($self, $sql) = @_; push @ran, $sql; return 0 }
package FakeSchema;
sub new     { return bless { dbh => FakeDbh->new }, $_[0] }
sub txn_do  { return $_[1]->() }
sub storage { return $_[0] }
sub dbh_do  { my ($self, $code) = @_; return $code->($self, $self->{dbh}) }
package main;

subtest 'display_name__tie__alphabetically_first' => sub {
  @ran = ();
  recompute_l3_domains(FakeSchema->new);
  my ($statement) = grep { /^WITH man AS/ } @ran;
  ok($statement, 'the recompute statement runs');
  (my $flat_statement = $statement) =~ s/\s+/ /g;
  like($flat_statement, qr/named AS \( SELECT DISTINCT ON \(d\.key\) d\.key,/, 'one name per domain key');
  like($flat_statement, qr/ORDER BY d\.key, count\(\*\) DESC, d\.vrf COLLATE "C"\)/, 'most common, then alphabetical');
  like($flat_statement, qr/l\.name IS DISTINCT FROM n\.name/, 'writes only a changed name');
  like($flat_statement, qr/l\.inferred_name NOT LIKE 'manual:%'/, 'manual domains keep their configured name');
};

subtest 'recompute__unchanged__returns_0' => sub {
  @ran = ();
  is(recompute_l3_domains(FakeSchema->new), 0);
};

done_testing;
