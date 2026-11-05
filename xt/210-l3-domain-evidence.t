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

my $sorted = sub {
  my $column = shift;
  return quotemeta("array_to_string(ARRAY(SELECT DISTINCT x FROM unnest($column) x WHERE x IS NOT NULL AND x <> '' ORDER BY x), ',')");
};

subtest 'evidence_key__isid_present__keyed_isid_before_rt' => sub {
  like($flat, qr/CASE WHEN d\.l3_isid IS NOT NULL THEN 'isid:' \|\| d\.l3_isid WHEN/, 'I-SID tested first');
  my $isid_at = index($flat, "'isid:'");
  my $rt_at   = index($flat, "'rt:'");
  ok($isid_at >= 0 && $rt_at > $isid_at, 'I-SID branch precedes the route-target branch');
};

subtest 'evidence_key__rt_arrays_unordered_with_duplicates__same_key' => sub {
  my ($imports, $exports) = ($sorted->('d.rt_import'), $sorted->('d.rt_export'));
  like($flat, qr/THEN 'rt:' \|\| $imports \|\| '\/' \|\| $exports/, 'de-duplicated, sorted, joined');
  like($flat, qr/> 0 THEN 'rt:'/, 'needs at least one non-empty set');
};

subtest 'evidence_key__rt_arrays_only_null_or_empty__falls_back_to_name' => sub {
  for my $column (qw/d.rt_import d.rt_export/) {
    my $filtered = quotemeta("ARRAY(SELECT DISTINCT x FROM unnest($column) x WHERE x IS NOT NULL AND x <> '' ORDER BY x)");
    like($flat, qr/$filtered/, "$column drops NULL and empty elements");
    like($flat, qr/array_length\($filtered, 1\)/, "$column has-route-targets test uses the filtered array");
  }
  unlike($flat, qr/array_length\(d\.rt_(?:import|export), 1\)/, 'never counts the raw arrays');
};

subtest 'evidence_key__no_isid_no_rt__keyed_name' => sub {
  like($flat, qr/ELSE 'name:' \|\| d\.vrf END AS key/);
};

subtest 'reason__each_evidence__exact_text' => sub {
  my ($imports, $exports) = ($sorted->('d.rt_import'), $sorted->('d.rt_export'));
  like($flat, qr/'shared L3 I-SID ' \|\| d\.l3_isid/);
  like($flat, qr/'same route targets import ' \|\| $imports \|\| ' export ' \|\| $exports/);
  like($flat, qr/ELSE 'same name ' \|\| d\.vrf END AS reason/);
};

subtest 'evidence__default_table__excluded_and_display_is_vrf' => sub {
  like($flat, qr/FROM device_vrf d WHERE d\.vrf <> ''/);
  like($flat, qr/d\.vrf AS display/);
  like($flat, qr/^SELECT d\.ip, d\.vrf,/, 'ip and vrf first');
};

my @ran;
package FakeDbh;
sub new { return bless {}, $_[0] }
sub do  { my ($self, $sql) = @_; push @ran, $sql; return '0E0' }
package FakeSchema;
sub new     { return bless { dbh => FakeDbh->new }, $_[0] }
sub txn_do  { return $_[1]->() }
sub storage { return $_[0] }
sub dbh_do  { my ($self, $code) = @_; return $code->($self, $self->{dbh}) }
package main;

subtest 'display_name__tie__alphabetically_first' => sub {
  @ran = ();
  recompute_l3_domains(FakeSchema->new);
  my ($rename) = grep { /^\s*UPDATE l3_domain\b/ } @ran;
  ok($rename, 'a rename statement runs');
  (my $flat_rename = $rename) =~ s/\s+/ /g;
  like($flat_rename, qr/SELECT DISTINCT ON \(m\.domain_id\) m\.domain_id, m\.vrf/, 'one name per domain');
  like($flat_rename, qr/ORDER BY m\.domain_id, count\(\*\) DESC, m\.vrf ASC/, 'most common, then alphabetical');
  like($flat_rename, qr/l\.name IS DISTINCT FROM top\.vrf/, 'writes only a changed name');
  like($flat_rename, qr/l\.inferred_name NOT LIKE 'manual:%'/, 'manual domains keep their configured name');
};

subtest 'recompute__unchanged__returns_0' => sub {
  @ran = ();
  is(recompute_l3_domains(FakeSchema->new), 0);
};

done_testing;
