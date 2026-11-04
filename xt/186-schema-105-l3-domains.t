#!/usr/bin/env perl

# Step 104-105 also records which VRF instances each device reports, groups
# them into L3 domains, and remembers the device that last reported an
# address. A row with vrf = '' is domain 0 with no rows present.

use strict;
use warnings;

use Test::More 0.88;

use App::Netdisco::DB::StepFile qw(parse_step_file);

my $step = parse_step_file('share/schema_versions/App-Netdisco-DB-104-105-PostgreSQL.sql');
my @statements = @{ $step->{statements} };

sub statements_matching {
  my ($pattern) = @_;
  return grep { $_ =~ $pattern } @statements;
}

subtest 'step_104_105__device_vrf__created_if_not_exists_with_ip_vrf_key' => sub {
  my @create = statements_matching(qr/^CREATE TABLE IF NOT EXISTS device_vrf\b/);
  is(scalar @create, 1, 'one CREATE TABLE IF NOT EXISTS');
  like($create[0], qr/\bip inet NOT NULL\b/, 'ip');
  like($create[0], qr/\bvrf text NOT NULL\b/, 'vrf is never NULL');
  like($create[0], qr/\brt_import text\[\] NOT NULL DEFAULT '\{\}'/, 'rt_import');
  like($create[0], qr/\brt_export text\[\] NOT NULL DEFAULT '\{\}'/, 'rt_export');
  like($create[0], qr/\bcomplete boolean NOT NULL DEFAULT false\b/, 'complete');
  like($create[0], qr/\bPRIMARY KEY \(ip, vrf\)/, 'key is (ip, vrf)');
  unlike($create[0], qr/;/, 'no semicolon inside the statement');
};

subtest 'step_104_105__l3_domain__default_domain_zero_seeded_idempotently' => sub {
  my @create = statements_matching(qr/^CREATE TABLE IF NOT EXISTS l3_domain\b/);
  is(scalar @create, 1, 'one CREATE TABLE IF NOT EXISTS');
  like($create[0], qr/\bid serial PRIMARY KEY\b/, 'serial key');
  my @seed = statements_matching(qr/^INSERT INTO l3_domain\b/);
  is(scalar @seed, 1, 'one seed statement');
  like($seed[0], qr/VALUES \(0, ''\)/, 'domain 0 has the empty name');
  like($seed[0], qr/ON CONFLICT \(id\) DO NOTHING$/, 'harmless when run twice');
};

subtest 'step_104_105__l3_domain__inferred_name_unique_index_created_if_not_exists' => sub {
  my @create = statements_matching(qr/^CREATE TABLE IF NOT EXISTS l3_domain\b/);
  like($create[0], qr/\binferred_name text\b(?! NOT NULL)/, 'nullable inferred_name column');
  my @index = statements_matching(qr/^CREATE UNIQUE INDEX IF NOT EXISTS l3_domain_inferred_name_key ON l3_domain \(inferred_name\)$/);
  is(scalar @index, 1, 'unique index on inferred_name, harmless twice');
  my @seed = statements_matching(qr/^INSERT INTO l3_domain\b/);
  unlike($seed[0], qr/inferred_name/, 'domain 0 leaves inferred_name NULL');
};

subtest 'step_104_105__l3_domain__inferred_name_also_added_for_tables_from_an_earlier_step' => sub {
  my @alter = statements_matching(qr/^ALTER TABLE l3_domain ADD COLUMN IF NOT EXISTS inferred_name text$/);
  is(scalar @alter, 1, 'one ALTER ... ADD COLUMN IF NOT EXISTS');
  my @all = map { s/^\s+//r } @{ [ statements_matching(qr/./) ] };
  my ($alter_at) = grep { $all[$_] =~ /^ALTER TABLE l3_domain ADD COLUMN/ } 0 .. $#all;
  my ($index_at) = grep { $all[$_] =~ /^CREATE UNIQUE INDEX IF NOT EXISTS l3_domain_inferred_name_key/ } 0 .. $#all;
  ok(defined $alter_at && defined $index_at && $alter_at < $index_at, 'column added before the index');
};

subtest 'step_104_105__l3_domain_member__source_limited_to_inferred_or_manual' => sub {
  my @create = statements_matching(qr/^CREATE TABLE IF NOT EXISTS l3_domain_member\b/);
  is(scalar @create, 1, 'one CREATE TABLE IF NOT EXISTS');
  like($create[0], qr/\bsource text NOT NULL CHECK \(source IN \('inferred', 'manual'\)\)/, 'source check');
  like($create[0], qr/\bPRIMARY KEY \(ip, vrf\)/, 'key is (ip, vrf)');
  ok(scalar(statements_matching(qr/^CREATE INDEX IF NOT EXISTS idx_l3_domain_member_vrf ON l3_domain_member \(vrf, domain_id\)$/)),
    'index by vrf and domain');
};

subtest 'step_104_105__router_last__added_bare_to_node_ip_and_subnets' => sub {
  foreach my $table (qw(node_ip subnets)) {
    my @add = statements_matching(qr/^ALTER TABLE $table ADD COLUMN\b.*\brouter_last\b/);
    is(scalar @add, 1, "$table: one ADD COLUMN router_last");
    is($add[0], "ALTER TABLE $table ADD COLUMN IF NOT EXISTS router_last inet", "$table: bare nullable column");
  }
  is(scalar(statements_matching(qr/^UPDATE\b.*\brouter_last\b/s)), 0, 'no UPDATE of router_last');
  is(scalar(statements_matching(qr/\brouter_last\b.*\b(?:DEFAULT|NOT NULL)\b/s)), 0, 'no default or NOT NULL');
};

subtest 'step_104_105__vrf_named_index__partial_on_active_named_vrfs' => sub {
  my @index = statements_matching(qr/^CREATE INDEX IF NOT EXISTS idx_node_ip_vrf_named_active\b/);
  is(scalar @index, 1, 'one CREATE INDEX IF NOT EXISTS');
  is($index[0], "CREATE INDEX IF NOT EXISTS idx_node_ip_vrf_named_active ON node_ip (vrf) WHERE active AND vrf <> ''",
    'vrf only, active named-VRF rows only');
  # the router_last index existed only in drafts of this step, so a released
  # database never has it to drop
  is(scalar(statements_matching(qr/\bidx_node_ip_router_last_active\b/)), 0, 'no draft-only DROP INDEX');
  # an index naming router_last makes every router_last change non-HOT
  is(scalar(statements_matching(qr/^CREATE\b.*\bINDEX\b.*\bON node_ip\b.*\brouter_last\b/s)), 0,
    'no node_ip index references router_last');
};

subtest 'step_104_105__l3_domain_of__create_or_replace_stable_returns_integer' => sub {
  my @function = statements_matching(qr/^CREATE OR REPLACE FUNCTION l3_domain_of\(/);
  is(scalar @function, 1, 'one function statement');
  like($function[0], qr/\(row_router inet, row_vrf text\)\s+RETURNS integer LANGUAGE sql STABLE PARALLEL SAFE\b/,
    'signature, STABLE and PARALLEL SAFE');
  like($function[0], qr/row_vrf = ''/, 'the default table is named');
  unlike($function[0], qr/;/, 'no semicolon inside the statement');
};

subtest 'result_classes__l3_domains__declared_as_the_step_creates_them' => sub {
  my %key = (DeviceVrf => [qw(ip vrf)], L3Domain => ['id'], L3DomainMember => [qw(ip vrf)]);
  foreach my $class (sort keys %key) {
    my $package = "App::Netdisco::DB::Result::$class";
    eval "require $package" or die $@;
    is_deeply([ $package->primary_columns ], $key{$class}, "$class primary key");
  }
  is(App::Netdisco::DB::Result::DeviceVrf->column_info('rt_import')->{data_type}, 'text[]', 'rt_import is text[]');
  is(App::Netdisco::DB::Result::DeviceVrf->column_info('rt_export')->{data_type}, 'text[]', 'rt_export is text[]');
  my $inferred = App::Netdisco::DB::Result::L3Domain->column_info('inferred_name');
  is($inferred->{data_type}, 'text', 'inferred_name data_type');
  is($inferred->{is_nullable}, 1, 'inferred_name nullable');
  is(App::Netdisco::DB::Result::L3DomainMember->column_info('source')->{data_type}, 'text', 'source');
  foreach my $class (qw(NodeIp Subnet)) {
    my $package = "App::Netdisco::DB::Result::$class";
    eval "require $package" or die $@;
    my $info = $package->column_info('router_last');
    is($info->{data_type}, 'inet', "$class router_last data_type");
    is($info->{is_nullable}, 1, "$class router_last nullable");
  }
  ok(App::Netdisco::DB::Result::Device->relationship_info($_), "Device $_") for qw(vrfs l3_domain_members);
  ok(App::Netdisco::DB::Result::L3DomainMember->relationship_info('domain'), 'L3DomainMember domain');
};

done_testing;
