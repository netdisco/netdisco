#!/usr/bin/env perl

use strict;
use warnings;

# recompute_l3_domains infers domains from VRF names alone. It must never
# touch a manual member, never delete domain 0, and keep domain ids stable by
# reusing a domain that already has the name. It runs on every discover with
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

sub run_recompute {
  @ran = (); $txns = 0; %rows_for = @_;
  my $count = recompute_l3_domains(FakeSchema->new);
  return ($count, @ran);
}

subtest 'recompute__statements__run_in_order_inside_one_locked_transaction' => sub {
  my ($count, @stmts) = run_recompute();
  is(scalar @stmts, 5, 'lock plus four statements');
  like($stmts[0][0], qr/pg_advisory_xact_lock\(\?, \?\)/, 'lock first');
  is_deeply([@{$stmts[0]}[1 .. 2]], [1729, 0], 'one global key');
  like($stmts[1][0], qr/INSERT INTO l3_domain\b/, 'create domains for new names');
  like($stmts[2][0], qr/^\s*DELETE FROM l3_domain_member/, 'delete members that no longer qualify');
  like($stmts[3][0], qr/INSERT INTO l3_domain_member/, 'insert missing members');
  like($stmts[4][0], qr/^\s*DELETE FROM l3_domain\b/, 'drop empty domains');
  is($txns, 1, 'one transaction');
};

subtest 'recompute__members_changed__returns_members_inserted_plus_deleted' => sub {
  my ($count) = run_recompute(member_delete => 2, member_insert => 3, domain_insert => 1, domain_delete => 1);
  is($count, 5, 'member rows inserted plus deleted');
};

subtest 'recompute__no_rows_written__returns_zero' => sub {
  my ($count) = run_recompute();
  is($count, 0);
};

subtest 'recompute__no_full_clear__deletes_only_members_that_no_longer_qualify' => sub {
  my (undef, undef, undef, $stale) = run_recompute();
  unlike($stale->[0], qr/^\s*DELETE FROM l3_domain_member WHERE source = 'inferred'\s*$/,
    'not every inferred member');
  like($stale->[0], qr/source = 'inferred'/, 'inferred members only, so manual rows are never deleted');
  like($stale->[0], qr/NOT EXISTS \(SELECT 1 FROM device_vrf d\s+JOIN l3_domain l ON l\.inferred_name = d\.vrf/,
    'kept only while its VRF is in device_vrf with a domain of that name');
  like($stale->[0], qr/d\.ip = \w+\.ip AND d\.vrf = \w+\.vrf/, 'matched on the pair');
  like($stale->[0], qr/l\.id = \w+\.domain_id/, 'a member in another domain is moved');
  like($stale->[0], qr/d\.vrf <> ''/, 'default table never a member');
};

subtest 'recompute__missing_members_only__any_member_of_the_pair_blocks_the_insert' => sub {
  my (undef, undef, $domains, undef, $members) = run_recompute();
  like($members->[0], qr/NOT EXISTS \(SELECT 1 FROM l3_domain_member m\s+WHERE m\.ip = d\.ip AND m\.vrf = d\.vrf\)/,
    'skips a pair with a member of either source');
  like($domains->[0], qr/NOT EXISTS \(SELECT 1 FROM l3_domain x WHERE x\.inferred_name = d\.vrf\)/,
    'a name with a domain is reused');
};

# otherwise a name held only by manual members gets a domain that the last
# statement deletes, on every run
subtest 'recompute__name_held_only_by_manual_members__no_domain_created' => sub {
  my (undef, undef, $domains) = run_recompute();
  like($domains->[0], qr/NOT EXISTS \(SELECT 1 FROM l3_domain_member m\s+WHERE m\.ip = d\.ip AND m\.vrf = d\.vrf AND m\.source = 'manual'\)/,
    'only a name with a pair left to infer');
};

subtest 'recompute__default_domain__never_deleted' => sub {
  my (undef, undef, undef, undef, undef, $cleanup) = run_recompute();
  like($cleanup->[0], qr/WHERE id <> 0\b/);
  like($cleanup->[0], qr/NOT EXISTS \(SELECT 1 FROM l3_domain_member/, 'any member keeps it');
  like($_->[0], qr/vrf <> ''/, 'default table skipped')
    for (grep { $_->[0] =~ /FROM device_vrf/ } @ran);
};

subtest 'recompute__reason__names_the_shared_name' => sub {
  my (undef, undef, undef, undef, $members) = run_recompute();
  like($members->[0], qr/'same name ' \|\| d\.vrf/);
  like($members->[0], qr/'inferred'/);
  like($members->[0], qr/JOIN l3_domain \w+ ON \w+\.inferred_name = d\.vrf/, 'domain by inferred name');
};

subtest 'recompute__duplicate_display_names__join_on_unique_inferred_name' => sub {
  my (undef, undef, $domains, $stale, $members) = run_recompute();
  like($domains->[0], qr/\(name, inferred_name\)\s+SELECT DISTINCT d\.vrf, d\.vrf\b/, 'both set from the VRF name');
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
