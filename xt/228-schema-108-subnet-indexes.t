#!/usr/bin/env perl

# Step 107-108 adds SP-GiST inet indexes that Subnet Utilization's
# containment join can use; a btree cannot serve "address within each stored
# subnet". #1833.

use strict;
use warnings;

use Test::More 0.88;

use App::Netdisco::DB::StepFile qw(parse_step_file);
use App::Netdisco::DB;

my $file = 'share/schema_versions/App-Netdisco-DB-107-108-PostgreSQL.sql';
ok(-f $file, "$file exists") or BAIL_OUT('step file missing');

my $step = parse_step_file($file);
my @creates = grep { /^CREATE INDEX/ } @{ $step->{statements} };

subtest 'step_107_108__parses__two_indexes_in_one_transaction' => sub {
  is($step->{no_transaction}, 0, 'runs in a transaction');
  is(scalar @creates, 2, 'two CREATE INDEX statements');
};

subtest 'step_107_108__indexes__spgist_inet_ops_if_not_exists' => sub {
  like($creates[0], qr/^CREATE INDEX IF NOT EXISTS idx_node_ip_ip_spgist ON node_ip USING spgist \(ip inet_ops\)\z/);
  like($creates[1], qr/^CREATE INDEX IF NOT EXISTS idx_device_ip_alias_spgist ON device_ip USING spgist \(alias inet_ops\)\z/);
};

# an index on subnets made the planner read all of node_ip instead
subtest 'step_107_108__no_subnets_index' => sub {
  ok(!(grep { /\bON subnets\b/ } @{ $step->{statements} }), 'no index on subnets');
};

subtest 'schema_version__is_108' => sub {
  is($App::Netdisco::DB::VERSION, 108);
};

done_testing;
