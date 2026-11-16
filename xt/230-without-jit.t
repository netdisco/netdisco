#!/usr/bin/env perl

# JIT compilation cost more than the indexed Subnet Utilization and node
# search queries on a narrow prefix, so those run through without_jit, which
# sets jit off for one transaction. PostgreSQL 10 has no jit setting. #1833.

use strict;
use warnings;

use Test::More 0.88;
use Try::Tiny;

use App::Netdisco::DB;

sub exception (&) { my $code = shift; return try { $code->(); undef } catch { $_ } }

package FakeDbh {
  sub new { my ($class, %args) = @_; return bless {%args}, $class }
  sub do  { my ($self, $sql) = @_; push @{ $self->{log} }, $sql; return 1 }
}

package FakeStorage {
  sub new { my ($class, $dbh) = @_; return bless { dbh => $dbh }, $class }
  sub dbh { return $_[0]->{dbh} }
}

package FakeSchema {
  use base 'App::Netdisco::DB';
  sub txn_do  { my ($self, $code) = @_; push @{ $self->{log} }, 'txn'; return $code->() }
  sub storage { return $_[0]->{storage} }
}

sub fake_schema {
  my $version = shift;
  my $log = [];
  my $dbh = FakeDbh->new(pg_server_version => $version, log => $log);
  my $schema = bless { log => $log, storage => FakeStorage->new($dbh) }, 'FakeSchema';
  return ($schema, $log);
}

subtest 'without_jit__pg11__sets_local_jit_off_inside_txn' => sub {
  my ($s, $log) = fake_schema(110000);
  is_deeply([ $s->without_jit(sub { push @$log, 'code'; (1, 2) }) ], [1, 2], 'returns the list');
  is_deeply($log, ['txn', 'SET LOCAL jit = off', 'code']);
};

subtest 'without_jit__pg10__no_set_still_in_txn' => sub {
  my ($s, $log) = fake_schema(100023);
  $s->without_jit(sub { push @$log, 'code' });
  is_deeply($log, ['txn', 'code']);
};

subtest 'without_jit__version_unknown__no_set' => sub {
  my ($s, $log) = fake_schema(undef);
  $s->without_jit(sub { push @$log, 'code' });
  is_deeply($log, ['txn', 'code']);
};

subtest 'without_jit__code_dies__error_propagates' => sub {
  my ($s) = fake_schema(180000);
  like(exception { $s->without_jit(sub { die "boom\n" }) }, qr/^boom/);
};

done_testing;
