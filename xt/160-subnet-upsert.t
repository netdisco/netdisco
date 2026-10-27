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
use App::Netdisco::DB;

set logger => 'null';

my $schema = do {
  local $SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /unversioned/ };
  my $s = App::Netdisco::DB->clone;
  $s->storage_type('::DBI::Pg');
  $s->connection('dbi:Pg:dbname=netdisco_xt_offline;host=127.0.0.1;port=1');
  $s;
};

my @ran;

package FakeDbh;
sub do {
  my ($self, $sql, undef, @binds) = @_;
  push @ran, [$sql, @binds];
  return 1;
}
sub quote_identifier { return '"' . ($_[1] =~ s/"/""/gr) . '"' }

package main;

my $fake = bless {}, 'FakeDbh';
no warnings qw(redefine once);
local *DBIx::Class::Storage::DBI::dbh_do = sub { my ($s, $code) = @_; $code->($s, $fake) };

subtest 'upsert_subnet__new_or_seen_net__shared_upsert_updating_last_discover' => sub {
  @ran = ();
  $schema->resultset('Subnet')->upsert_subnet('192.0.2.0/24', 'to_timestamp(1)::timestamp');
  is(scalar @ran, 1, 'one statement');
  my ($sql, @binds) = @{ $ran[0] };
  is($sql, 'INSERT INTO "subnets" ("last_discover", "net") VALUES (to_timestamp(1)::timestamp, ?)'
    . ' ON CONFLICT ("net") DO UPDATE SET "last_discover" = EXCLUDED."last_discover"'
    . ' WHERE ("subnets"."last_discover") IS DISTINCT FROM (EXCLUDED."last_discover")', 'sql');
  is_deeply(\@binds, ['192.0.2.0/24'], 'the net is bound, not interpolated');
};

subtest 'upsert_subnet__no_net__writes_nothing' => sub {
  @ran = ();
  $schema->resultset('Subnet')->upsert_subnet(undef, 'LOCALTIMESTAMP');
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
