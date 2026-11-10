#!/usr/bin/env perl

use strict;
use warnings;

# recompute_l3_domains puts each VRF in the domain of its evidence key (I-SID,
# route targets, else the VRF name) unless a vrf_domains entry places it. It
# owns the manual member rows too (xt/211), never deletes domain 0, and keeps
# domain ids stable by reusing a domain that already has the key. It runs after a discover with
# store_vrfs on (xt/213 says when), so it writes only what changed: an unchanged network deletes
# and inserts nothing. Only the database handle is faked; these check the SQL
# and binds sent.

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use App::Netdisco;
use App::Netdisco::Util::L3Domain qw/recompute_l3_domains with_l3_domain_lock/;

my (@ran, $txns, $returns);

package FakeDbh;
sub new { return bless {}, $_[0] }
sub do  { my ($self, $sql, undef, @binds) = @_; push @ran, [$sql, @binds]; return '0E0' }
sub selectrow_array { my ($self, $sql, undef, @binds) = @_; push @ran, [$sql, @binds]; return $returns }

package FakeSchema;
sub new     { return bless { dbh => FakeDbh->new }, $_[0] }
sub txn_do  { ++$txns; return $_[1]->() }
sub storage { return $_[0] }
sub dbh_do  { my ($self, $code) = @_; return $code->($self, $self->{dbh}) }

package main;

# returns the count and the one statement after the lock, whitespace folded
sub run_recompute {
  @ran = (); $txns = 0; $returns = shift // 0;
  my $count = recompute_l3_domains(FakeSchema->new);
  (my $flat = $ran[1][0] // '') =~ s/\s+/ /g;
  return ($count, $flat);
}

# the text of one named CTE of the statement
sub cte {
  my ($flat, $name) = @_;
  return $flat =~ m/\b$name AS \( ?(.*?) ?\)(?:, \w+ AS \(| SELECT \(SELECT count)/ ? $1 : '';
}

subtest 'recompute__statements__lock_then_one_statement_in_one_transaction' => sub {
  run_recompute();
  is(scalar @ran, 2, 'the lock and one statement');
  like($ran[0][0], qr/pg_advisory_xact_lock\(\?, \?\)/, 'lock first');
  is_deeply([@{$ran[0]}[1 .. 2]], [1729, 0], 'one global key');
  like($ran[1][0], qr/^WITH man AS/, 'then the statement');
  is(scalar @{ $ran[1] } - 1, 4, 'the four manual arrays are bound');
  unlike($ran[1][0], qr/TEMP TABLE/, 'no temporary table');
  is($txns, 1, 'one transaction');
};

# each statement that read the evidence used to compute the key of every
# device_vrf row itself; at 10k rows that cost 722 ms on 9.6 under the global lock
subtest 'recompute__evidence__computed_once_into_desired' => sub {
  my (undef, $flat) = run_recompute();
  my $reads = () = $flat =~ m/FROM device_vrf\b/g;
  is($reads, 1, 'device_vrf read once');
  like(cte($flat, 'desired'), qr/FROM device_vrf\b/, 'by the desired set');
  my $uses = () = $flat =~ m/FROM desired d\b/g;
  cmp_ok($uses, '>', 1, 'desired is read more than once, so the server materializes it');
};

# the server's collation differs across glibc versions, so a tie or an
# array element order must be decided by bytes
subtest 'recompute__orderings__use_C_collation' => sub {
  my (undef, $flat) = run_recompute();
  like(cte($flat, 'named'), qr/ORDER BY d\.key, count\(\*\) DESC, d\.vrf COLLATE "C"/, 'display name: most common, then bytewise');
};

subtest 'recompute__returns__the_statement_count' => sub {
  my ($count, $flat) = run_recompute(9);
  is($count, 9, 'what the statement returns');
  like($flat, qr/SELECT \(SELECT count\(\*\) FROM gone\) \+ 2 \* \(SELECT count\(\*\) FROM moved\) \+ \(SELECT count\(\*\) FROM added\) \+ \(SELECT count\(\*\) FROM renamed\) \+ \(SELECT count\(\*\) FROM emptied\)$/,
    'members deleted, moved (counted as the delete and insert they replace), inserted, plus domains renamed or deleted');
};

subtest 'recompute__no_rows_written__returns_zero' => sub {
  my ($count) = run_recompute(0);
  is($count, 0);
};

# every CTE reads the snapshot from before any of them writes, so each member
# row must be touched by at most one of them
subtest 'recompute__members__deleted_moved_or_added_never_two' => sub {
  my (undef, $flat) = run_recompute();
  like(cte($flat, 'gone'), qr/^DELETE FROM l3_domain_member m WHERE NOT EXISTS \(SELECT 1 FROM desired d WHERE d\.ip = m\.ip AND d\.vrf = m\.vrf\)/,
    'deleted: the pair is no longer wanted');
  unlike(cte($flat, 'gone'), qr/source = 'inferred'/, 'manual rows are deleted when no entry wants them');
  like(cte($flat, 'moved'), qr/^UPDATE l3_domain_member m SET domain_id = t\.domain_id, reason = t\.reason, source = t\.source FROM target t WHERE t\.ip = m\.ip AND t\.vrf = m\.vrf AND \(t\.domain_id <> m\.domain_id/,
    'moved: wanted, in another domain');
  like(cte($flat, 'added'), qr/WHERE NOT EXISTS \(SELECT 1 FROM l3_domain_member m WHERE m\.ip = t\.ip AND m\.vrf = t\.vrf\)/,
    'added: no member of either source for the pair');
};

# domains a CTE inserts are invisible to the others through l3_domain
# a member that stayed in its domain kept its old reason, so a VRF placed by a
# join and then named directly by vrf_domains still said it was joined
subtest 'recompute__same_domain_new_reason__member_rewritten' => sub {
  my (undef, $flat) = run_recompute();
  like(cte($flat, 'moved'), qr/OR t\.reason IS DISTINCT FROM m\.reason OR t\.source <> m\.source\)/,
    'a changed reason or source is written too');
};

subtest 'recompute__new_domains__ids_from_returning_and_named_on_insert' => sub {
  my (undef, $flat) = run_recompute();
  like(cte($flat, 'new_dom'), qr/^INSERT INTO l3_domain \(name, inferred_name\) SELECT n\.name, n\.key FROM named n WHERE NOT EXISTS \(SELECT 1 FROM l3_domain x WHERE x\.inferred_name = n\.key\) RETURNING id, inferred_name$/,
    'a key with a domain is reused; a new one is named as the rename would name it');
  like(cte($flat, 'dom'), qr/UNION ALL SELECT id, inferred_name FROM new_dom$/, 'the id lookup includes the new domains');
  like(cte($flat, 'target'), qr/JOIN dom m ON m\.inferred_name = d\.key$/, 'members find their domain through it');
};

subtest 'recompute__rename__existing_inferred_domains_only' => sub {
  my (undef, $flat) = run_recompute();
  my $renamed = cte($flat, 'renamed');
  like($renamed, qr/^UPDATE l3_domain l SET name = n\.name FROM named n WHERE l\.inferred_name = n\.key/, 'named from the wanted members');
  like($renamed, qr/l\.name IS DISTINCT FROM n\.name/, 'writes only a changed name');
  like($renamed, qr/l\.inferred_name NOT LIKE 'manual:%'/, 'manual domains keep their configured name');
  like(cte($flat, 'named'), qr/CASE WHEN d\.key LIKE 'manual:%' THEN min\(d\.display\) ELSE d\.vrf END AS name/, 'a manual domain is named as configured');
};

# otherwise a name held only by manual pairs gets a domain that the empty
# domain delete removes, on every run
subtest 'recompute__name_held_only_by_manual_pairs__no_domain_created' => sub {
  my (undef, $flat) = run_recompute();
  like(cte($flat, 'desired'), qr/WHERE NOT EXISTS \(SELECT 1 FROM man WHERE man\.ip = e\.ip AND man\.vrf = e\.vrf\)$/,
    'a pair a manual entry claims is not also inferred, so its evidence key makes no domain');
};

subtest 'recompute__default_domain__never_deleted' => sub {
  my (undef, $flat) = run_recompute();
  like(cte($flat, 'emptied'), qr/^DELETE FROM l3_domain l WHERE l\.id <> 0 AND NOT EXISTS \(SELECT 1 FROM desired d WHERE d\.key = l\.inferred_name\)/,
    'any wanted member keeps it');
  like(cte($flat, 'desired'), qr/WHERE d\.vrf <> ''/, 'default table never a member (in the evidence)');
};

subtest 'recompute__reason__comes_from_the_evidence' => sub {
  my (undef, $flat) = run_recompute();
  like(cte($flat, 'added'), qr/SELECT t\.ip, t\.vrf, t\.domain_id, t\.reason, t\.source FROM target t/);
  like(cte($flat, 'desired'), qr/'same name ' \|\| d\.vrf/, 'evidence fragment embedded');
  like(cte($flat, 'desired'), qr/'inferred'::text AS source/, 'evidence rows are inferred members');
};

subtest 'recompute__duplicate_display_names__join_on_unique_inferred_name' => sub {
  my (undef, $flat) = run_recompute();
  unlike(cte($flat, $_), qr/\bl\.name\b|\bm\.name\b/, "$_ never joins on a display name") for qw/target gone moved added/;
};

subtest 'with_l3_domain_lock__code__runs_after_the_lock_in_one_transaction' => sub {
  @ran = (); $txns = 0;
  my $result = with_l3_domain_lock(FakeSchema->new, sub { push @ran, ['code']; return 42 });
  is($txns, 1, 'one transaction');
  like($ran[0][0], qr/^SELECT pg_advisory_xact_lock\(\?, \?\)$/, 'lock first');
  is_deeply([@{$ran[0]}[1 .. 2]], [1729, 0], 'the L3 domain key');
  is($ran[1][0], 'code', 'then the code');
  is($result, 42, 'returns what the code returns');
};

done_testing;
