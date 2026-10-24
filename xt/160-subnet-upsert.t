#!/usr/bin/env perl

use strict;
use warnings;

# Subnets are written with one INSERT ... ON CONFLICT, so two pollers that
# see the same new subnet cannot both insert it and fail on subnets_pkey.
#
# Only the database handle is faked; these check the SQL and binds sent.
# The concurrency itself needs a real database and is not tested here.

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Path::Tiny;
use App::Netdisco;
use Dancer ':tests';
use App::Netdisco::DB::ResultSet::Subnet;

set logger => 'null';

my @ran;

package FakeDbh;
sub new { return bless {}, $_[0] }
sub do  { my ($self, $sql, undef, @binds) = @_; push @ran, [$sql, @binds]; return 1 }

package FakeStorage;
sub new    { return bless { dbh => FakeDbh->new }, $_[0] }
sub dbh_do { my ($self, $code) = @_; return $code->($self, $self->{dbh}) }

package FakeSource;
sub new     { return bless { storage => FakeStorage->new }, $_[0] }
sub storage { return $_[0]{storage} }

package FakeSubnetRS;
our @ISA = ('App::Netdisco::DB::ResultSet::Subnet');
sub new           { return bless { source => FakeSource->new }, $_[0] }
sub result_source { return $_[0]{source} }

package main;

subtest 'upsert_subnet__new_or_seen_net__one_insert_on_conflict_updating_last_discover' => sub {
  @ran = ();
  FakeSubnetRS->new->upsert_subnet('192.0.2.0/24', 'to_timestamp(1)::timestamp');
  is(scalar @ran, 1, 'one statement');
  my ($sql, @binds) = @{ $ran[0] };
  like($sql, qr/^INSERT INTO subnets \(net, last_discover\) VALUES \(\?, to_timestamp\(1\)::timestamp\)/);
  like($sql, qr/ON CONFLICT \(net\) DO UPDATE SET last_discover = EXCLUDED\.last_discover$/);
  is_deeply(\@binds, ['192.0.2.0/24'], 'the net is bound, not interpolated');
};

subtest 'upsert_subnet__no_net__writes_nothing' => sub {
  @ran = ();
  FakeSubnetRS->new->upsert_subnet(undef, 'LOCALTIMESTAMP');
  is(scalar @ran, 0);
};

# update_or_create with FOR UPDATE locks nothing when the row is absent,
# so it would let two pollers insert the same new subnet
subtest 'subnet_writers__discover_and_arpnip__use_the_upsert' => sub {
  foreach my $file (qw{
      lib/App/Netdisco/Worker/Plugin/Discover/Properties.pm
      lib/App/Netdisco/Worker/Plugin/Arpnip/Subnets.pm }) {
    my $source = Path::Tiny::path($file)->slurp_utf8;
    like($source, qr/resultset\('Subnet'\)\s*->upsert_subnet\(/, "$file upserts");
    unlike($source, qr/resultset\('Subnet'\)\s*->update_or_create/, "$file has no update_or_create left");
  }
};

done_testing;
