#!/usr/bin/env perl

use strict;
use warnings;

# recompute_l3_domains puts each VRF in the domain of its evidence key (I-SID,
# route targets, else the VRF name) unless a vrf_domains entry places it. It
# owns the manual member rows too (xt/211), never deletes domain 0, and keeps
# domain ids stable by reusing a domain that already has the key. It runs on every discover with
# store_vrfs on, so it writes only what changed: an unchanged network deletes
# and inserts nothing. Only the database handle is faked; these check the SQL
# and binds sent.

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use App::Netdisco;
use App::Netdisco::Util::L3Domain qw/recompute_l3_domains with_l3_domain_lock/;

my (@ran, $txns, %rows_for);

# rows each statement reports, by the table it writes
sub statement_kind {
  my $sql = shift;
  return 'member_delete' if $sql =~ /^\s*DELETE FROM l3_domain_member/;
  return 'member_insert' if $sql =~ /INSERT INTO l3_domain_member/;
  return 'domain_rename' if $sql =~ /^\s*UPDATE l3_domain\b/;
  return 'domain_insert' if $sql =~ /INSERT INTO l3_domain\b/;
  return 'domain_delete' if $sql =~ /^\s*DELETE FROM l3_domain\b/;
  return 'other';
}

package FakeDbh;
sub new { return bless {}, $_[0] }
sub do  {
  my ($self, $sql, undef, @binds) = @_;
  push @ran, [$sql, @binds];
  return $rows_for{ main::statement_kind($sql) } // '0E0';
}

package FakeSchema;
sub new     { return bless { dbh => FakeDbh->new }, $_[0] }
sub txn_do  { ++$txns; return $_[1]->() }
sub storage { return $_[0] }
sub dbh_do  { my ($self, $code) = @_; return $code->($self, $self->{dbh}) }

package main;

# the evidence is computed once into a temp table, so the two statements that
# build it are dropped from the list the per-statement tests index into
sub run_recompute {
  @ran = (); $txns = 0; %rows_for = @_;
  my $count = recompute_l3_domains(FakeSchema->new);
  return ($count, grep { $_->[0] !~ /^\s*(?:SET LOCAL|DROP TABLE|CREATE TEMP TABLE)/ } @ran);
}

subtest 'recompute__statements__run_in_order_inside_one_locked_transaction' => sub {
  run_recompute();
  my @stmts = @ran;
  is(scalar @stmts, 10, 'lock, three temp-table statements, five writes, and the quiet-drop setting');
  like($stmts[0][0], qr/pg_advisory_xact_lock\(\?, \?\)/, 'lock first');
  is_deeply([@{$stmts[0]}[1 .. 2]], [1729, 0], 'one global key');
  like($stmts[1][0], qr/^\s*SET LOCAL client_min_messages = warning$/, 'no NOTICE from the drop on stderr');
  like($stmts[2][0], qr/^\s*DROP TABLE IF EXISTS pg_temp\.l3_domain_evidence, pg_temp\.l3_domain_desired$/, 'a leftover from an earlier call in this transaction goes');
  like($stmts[3][0], qr/^\s*CREATE TEMP TABLE l3_domain_evidence ON COMMIT DROP AS\b/, 'evidence computed once');
  like($stmts[4][0], qr/^\s*CREATE TEMP TABLE l3_domain_desired ON COMMIT DROP AS\b/, 'desired set built from it');
  like($stmts[5][0], qr/INSERT INTO l3_domain\b/, 'create domains for new names');
  like($stmts[6][0], qr/^\s*DELETE FROM l3_domain_member/, 'delete members that no longer qualify');
  like($stmts[7][0], qr/INSERT INTO l3_domain_member/, 'insert missing members');
  like($stmts[8][0], qr/^\s*UPDATE l3_domain\b/, 'rename domains after their majority name');
  like($stmts[9][0], qr/^\s*DELETE FROM l3_domain\b/, 'drop empty domains');
  is($txns, 1, 'one transaction');
};

# each statement that read the evidence used to compute the key of every
# device_vrf row itself; at 10k rows that cost 722 ms on 9.6 under the global lock
subtest 'recompute__evidence__computed_once_and_read_by_the_member_statements' => sub {
  run_recompute();
  my @computes = grep { $_->[0] =~ /FROM device_vrf/ } @ran;
  is(scalar @computes, 1, 'device_vrf read by one statement');
  like($computes[0][0], qr/^\s*CREATE TEMP TABLE l3_domain_evidence/, 'the one that builds the evidence table');
  my ($desired) = grep { $_->[0] =~ /^\s*CREATE TEMP TABLE l3_domain_desired/ } @ran;
  like($desired->[0], qr/FROM pg_temp\.l3_domain_evidence e\b/, 'the desired set reads the evidence table');
  is(scalar @{ $desired } - 1, 4, 'the four manual arrays are bound there');
  for my $kind ([ 'domain create' => 5 ], [ 'stale delete' => 6 ], [ 'member insert' => 7 ]) {
    my ($label, $at) = @$kind;
    like($ran[$at][0], qr/FROM pg_temp\.l3_domain_desired e\b/, "$label reads the temp table");
    is(scalar @{ $ran[$at] }, 1, "$label binds nothing");
    unlike($ran[$at][0], qr/rt_import|unnest|device_vrf/, "$label recomputes no evidence");
  }
};

# the server's collation differs across glibc versions, so a tie or an
# array element order must be decided by bytes
subtest 'recompute__orderings__use_C_collation' => sub {
  my (undef, undef, $domains) = run_recompute();
  like($domains->[0], qr/ORDER BY e\.key, e\.display COLLATE "C"/, 'display tie on domain create');
  my (undef, undef, undef, undef, undef, $rename) = run_recompute();
  like($rename->[0], qr/count\(\*\) DESC, m\.vrf COLLATE "C" ASC/, 'display tie on rename');
};

subtest 'recompute__members_changed__returns_members_inserted_plus_deleted_plus_renamed' => sub {
  my ($count) = run_recompute(member_delete => 2, member_insert => 3, domain_rename => 4, domain_insert => 1, domain_delete => 1);
  is($count, 9, 'member rows inserted plus deleted plus domains renamed');
};

subtest 'recompute__no_rows_written__returns_zero' => sub {
  my ($count) = run_recompute();
  is($count, 0);
};

subtest 'recompute__no_full_clear__deletes_only_members_that_no_longer_qualify' => sub {
  my (undef, undef, undef, $stale) = run_recompute();
  unlike($stale->[0], qr/^\s*DELETE FROM l3_domain_member WHERE source = 'inferred'\s*$/,
    'not every inferred member');
  unlike($stale->[0], qr/source = 'inferred'/, 'manual rows are deleted when no entry wants them');
  like($stale->[0], qr/NOT EXISTS \(SELECT 1 FROM pg_temp\.l3_domain_desired e\s+JOIN l3_domain l ON l\.inferred_name = e\.key/s,
    'kept only while its evidence key has that domain');
  like($stale->[0], qr/e\.ip = \w+\.ip AND e\.vrf = \w+\.vrf/, 'matched on the pair');
  like($stale->[0], qr/l\.id = \w+\.domain_id/, 'a member in another domain is moved');
  like((grep { $_->[0] =~ /^\s*CREATE TEMP TABLE l3_domain_evidence/ } @ran)[0][0], qr/d\.vrf <> ''/, 'default table never a member (in the evidence)');
};

subtest 'recompute__missing_members_only__any_member_of_the_pair_blocks_the_insert' => sub {
  my (undef, undef, $domains, undef, $members) = run_recompute();
  like($members->[0], qr/NOT EXISTS \(SELECT 1 FROM l3_domain_member m\s+WHERE m\.ip = e\.ip AND m\.vrf = e\.vrf\)/,
    'skips a pair with a member of either source');
  like($domains->[0], qr/NOT EXISTS \(SELECT 1 FROM l3_domain x WHERE x\.inferred_name = e\.key\)/,
    'a name with a domain is reused');
};

# otherwise a name held only by manual pairs gets a domain that the last
# statement deletes, on every run
subtest 'recompute__name_held_only_by_manual_pairs__no_domain_created' => sub {
  my (undef, undef, $domains) = run_recompute();
  like((grep { $_->[0] =~ /^\s*CREATE TEMP TABLE l3_domain_desired/ } @ran)[0][0], qr/WHERE NOT EXISTS \(SELECT 1 FROM man WHERE man\.ip = e\.ip AND man\.vrf = e\.vrf\)/s,
    'a pair a manual entry claims is not also inferred, so its evidence key makes no domain');
};

subtest 'recompute__default_domain__never_deleted' => sub {
  my (undef, undef, undef, undef, undef, undef, $cleanup) = run_recompute();
  like($cleanup->[0], qr/WHERE id <> 0\b/);
  like($cleanup->[0], qr/NOT EXISTS \(SELECT 1 FROM l3_domain_member/, 'any member keeps it');
  like($_->[0], qr/vrf <> ''/, 'default table skipped')
    for (grep { $_->[0] =~ /FROM device_vrf/ } @ran);
};

subtest 'recompute__reason__comes_from_the_evidence' => sub {
  my (undef, undef, undef, undef, $members) = run_recompute();
  like($members->[0], qr/SELECT e\.ip, e\.vrf, l\.id, e\.reason, e\.source/);
  like((grep { $_->[0] =~ /^\s*CREATE TEMP TABLE l3_domain_evidence/ } @ran)[0][0], qr/'same name ' \|\| d\.vrf/, 'evidence fragment embedded');
  like((grep { $_->[0] =~ /^\s*CREATE TEMP TABLE l3_domain_desired/ } @ran)[0][0], qr/'inferred'::text AS source/, 'evidence rows are inferred members');
  like($members->[0], qr/JOIN l3_domain \w+ ON \w+\.inferred_name = e\.key/, 'domain by inferred name');
};

subtest 'recompute__duplicate_display_names__join_on_unique_inferred_name' => sub {
  my (undef, undef, $domains, $stale, $members) = run_recompute();
  like($domains->[0], qr/\(name, inferred_name\)\s+SELECT DISTINCT ON \(e\.key\) e\.display, e\.key\b/, 'name from a member, key from the evidence');
  unlike($_->[0], qr/\bl\.name\b/, 'display name never joined') for ($stale, $members);
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
