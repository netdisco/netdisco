#!/usr/bin/env perl

# The config_version counter lets each process notice that the ACL Manager
# changed without reading the ACL tables on every request. It is bumped in
# Perl, in the same transaction as the write, so these tests pin the order
# (block first, bump after) and that a failed block never bumps.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;

use Dancer qw/:syntax :script !pass/;
use App::Netdisco::DB::StepFile qw(parse_step_file);
use App::Netdisco::DB;
use App::Netdisco::Util::ManagedConfig qw(acl_txn_do tenant_key _read_config_version);

my $step = parse_step_file('share/schema_versions/App-Netdisco-DB-105-106-PostgreSQL.sql');

subtest 'step_105_106__creates_config_version_and_seeds_acl' => sub {
  is($step->{no_transaction}, 0, 'runs in a transaction');
  is(scalar(grep { /CREATE TABLE IF NOT EXISTS config_version/ } @{ $step->{statements} }), 1, 'creates the table');
  is(scalar(grep { /INSERT INTO config_version.*'acl'.*ON CONFLICT/s } @{ $step->{statements} }), 1, 'seeds acl');
};

subtest 'db_version__is_106' => sub {
  is($App::Netdisco::DB::VERSION, 106);
};

my (@log, @schema_calls, $dbh_result);
{
  # the fakes log [$sql, @bind], dropping DBI's attribute argument
  package Fake::Storage;
  sub dbh_do { my ($self, $code, @args) = @_; return $code->($self, bless({}, 'Fake::Dbh'), @args) }
  package Fake::Dbh;
  sub do { my ($self, $sql, $attr, @bind) = @_; push @log, [$sql, @bind]; return 1 }
  sub selectrow_array { my ($self, $sql, $attr, @bind) = @_; push @log, [$sql, @bind]; return $dbh_result }
  package Fake::Schema;
  sub txn_do { my ($self, $code) = @_; return wantarray ? ($code->()) : scalar $code->() }
  sub storage { bless {}, 'Fake::Storage' }
}
{
  no warnings 'redefine';
  *App::Netdisco::Util::ManagedConfig::schema = sub {
    push @schema_calls, $_[0];
    return bless {}, 'Fake::Schema';
  };
}

my $bump = ['UPDATE config_version SET version = version + 1 WHERE scope = ?', 'acl'];

subtest 'aclTxnDo__a_successful_block__bumps_once_after_it' => sub {
  @log = ();
  my @ret = acl_txn_do(sub { push @log, 'block'; return ('a', 'b') });
  is_deeply(\@log, ['block', $bump], 'block then one bump');
  is_deeply(\@ret, ['a', 'b'], 'returns the block values');
};

subtest 'aclTxnDo__a_block_that_dies__does_not_bump_and_rethrows' => sub {
  @log = ();
  eval { acl_txn_do(sub { die "boom\n" }) };
  is($@, "boom\n", 'error propagates');
  is(scalar(grep { ref $_ && $_->[0] =~ /^UPDATE/ } @log), 0, 'no bump');
};

subtest 'aclTxnDo__uses_the_current_tenant' => sub {
  @schema_calls = ();
  var tenant => 'east';
  acl_txn_do(sub { 1 });
  is($schema_calls[0], 'east', 'east');
  is(tenant_key(), 'east', 'tenant_key');
  @schema_calls = ();
  var tenant => undef;
  acl_txn_do(sub { 1 });
  is($schema_calls[0], 'netdisco', 'default');
  is(tenant_key(), 'netdisco', 'tenant_key default');
};

subtest 'readConfigVersion__returns_the_acl_counter' => sub {
  @log = ();
  $dbh_result = 7;
  is(_read_config_version('netdisco'), 7, 'value');
  is_deeply($log[0], ['SELECT version FROM config_version WHERE scope = ?', 'acl'], 'sql and bind');
};

done_testing;
