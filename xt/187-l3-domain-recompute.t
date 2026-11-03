#!/usr/bin/env perl

use strict;
use warnings;

# recompute_l3_domains infers domains from VRF names alone. It must never
# touch a manual member, never delete domain 0, and keep domain ids stable by
# reusing a domain that already has the name. Only the database handle is
# faked; these check the SQL and binds sent.

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use App::Netdisco;
use App::Netdisco::Util::L3Domain qw/recompute_l3_domains/;

my (@ran, $txns, $step3_rows);

package FakeDbh;
sub new { return bless {}, $_[0] }
sub do  {
  my ($self, $sql, undef, @binds) = @_;
  push @ran, [$sql, @binds];
  return $sql =~ /INSERT INTO l3_domain_member/ ? $step3_rows : '0E0';
}

package FakeSchema;
sub new     { return bless { dbh => FakeDbh->new }, $_[0] }
sub txn_do  { ++$txns; return $_[1]->() }
sub storage { return $_[0] }
sub dbh_do  { my ($self, $code) = @_; return $code->($self, $self->{dbh}) }

package main;

sub run_recompute {
  @ran = (); $txns = 0; $step3_rows = shift // '0E0';
  my $count = recompute_l3_domains(FakeSchema->new);
  return ($count, @ran);
}

subtest 'recompute__statements__run_in_order_inside_one_locked_transaction' => sub {
  my ($count, @stmts) = run_recompute(3);
  is(scalar @stmts, 5, 'lock plus four statements');
  like($stmts[0][0], qr/pg_advisory_xact_lock\(\?, \?\)/, 'lock first');
  is_deeply([@{$stmts[0]}[1 .. 2]], [1729, 0], 'one global key');
  like($stmts[1][0], qr/^\s*DELETE FROM l3_domain_member/, 'clear inferred');
  like($stmts[2][0], qr/INSERT INTO l3_domain\b/, 'create domains');
  like($stmts[3][0], qr/INSERT INTO l3_domain_member/, 'insert members');
  like($stmts[4][0], qr/^\s*DELETE FROM l3_domain\b/, 'drop empty domains');
  is($txns, 1, 'one transaction');
  is($count, 3, 'returns the members written');
};

subtest 'recompute__no_rows_written__returns_zero' => sub {
  my ($count) = run_recompute('0E0');
  is($count, 0);
};

subtest 'recompute__inferred_only__manual_members_never_deleted_or_replaced' => sub {
  my (undef, undef, $clear, $domains, $members) = run_recompute();
  like($clear->[0], qr/WHERE source = 'inferred'/, 'delete names inferred');
  like($members->[0], qr/NOT EXISTS \(SELECT 1 FROM l3_domain_member m\b[^)]*source = 'manual'/,
    'insert skips manual pairs');
  like($members->[0], qr/m\.ip = d\.ip AND m\.vrf = d\.vrf/, 'matched on the pair');
  like($domains->[0], qr/NOT EXISTS \(SELECT 1 FROM l3_domain x WHERE x\.inferred_name = d\.vrf\)/,
    'a name with a domain is reused');
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
  my (undef, undef, undef, $domains, $members) = run_recompute();
  like($domains->[0], qr/\(name, inferred_name\)\s+SELECT DISTINCT d\.vrf, d\.vrf\b/, 'both set from the VRF name');
  unlike($members->[0], qr/\bl\.name\b/, 'display name never joined');
};

done_testing;
