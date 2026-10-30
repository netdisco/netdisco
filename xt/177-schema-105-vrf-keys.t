#!/usr/bin/env perl

# Step 104-105 adds a vrf key to device_ip and subnets, and a view that
# resolves an alias address to one device. The default table is vrf = '',
# never NULL, so that upserts can name the key.

use strict;
use warnings;

use Test::More 0.88;

use App::Netdisco::DB::StepFile qw(parse_step_file);
use App::Netdisco::DB;

my $step = parse_step_file('share/schema_versions/App-Netdisco-DB-104-105-PostgreSQL.sql');
my @statements = @{ $step->{statements} };

sub position_of {
  my ($wanted) = @_;
  my @found = grep { $statements[$_] eq $wanted } 0 .. $#statements;
  return @found ? $found[0] : undef;
}

subtest 'step_104_105__parses__one_transaction' => sub {
  is($step->{no_transaction}, 0, 'runs in a transaction');
};

subtest 'step_104_105__add_column__not_null_default_empty_in_one_statement' => sub {
  foreach my $table (qw(device_ip subnets)) {
    my @add = grep { /^ALTER TABLE $table ADD COLUMN/ } @statements;
    is(scalar @add, 1, "$table: one ADD COLUMN");
    is($add[0], "ALTER TABLE $table ADD COLUMN IF NOT EXISTS vrf text NOT NULL DEFAULT ''",
      "$table: column, default and NOT NULL in one statement");
    is(scalar(grep { /^(UPDATE $table |ALTER TABLE $table ALTER COLUMN vrf)/ } @statements), 0,
      "$table: no separate default, backfill or NOT NULL statement");
  }
};

subtest 'step_104_105__primary_keys__dropped_if_exists_and_widened' => sub {
  my %key = (device_ip => 'ip, alias, vrf', subnets => 'net, vrf');
  foreach my $table (sort keys %key) {
    my $drop = position_of("ALTER TABLE $table DROP CONSTRAINT IF EXISTS ${table}_pkey");
    my $add  = position_of("ALTER TABLE $table ADD CONSTRAINT ${table}_pkey PRIMARY KEY ($key{$table})");
    ok(defined $drop, "$table: pkey dropped if exists");
    ok(defined $add, "$table: pkey widened");
    ok(defined $drop && defined $add && $drop < $add, "$table: drop before add");
  }
};

subtest 'step_104_105__vrf_function__one_parallel_safe_statement_costed_as_cheap' => sub {
  my @functions = grep { /^CREATE OR REPLACE FUNCTION device_ip_vrf_row_resolves\(/ } @statements;
  is(scalar @functions, 1, 'one function statement');
  unlike($functions[0], qr/;/, 'no semicolon inside the statement');
  like($functions[0], qr/\bLANGUAGE sql STABLE PARALLEL SAFE COST 1 AS\b/,
    'STABLE, PARALLEL SAFE and COST 1, so the planner keeps device_ip plans');
  like($functions[0], qr/SELECT NOT EXISTS \(SELECT 1 FROM device_ip x/, 'one probe of device_ip');
};

subtest 'step_104_105__view__one_scan_of_device_ip_with_no_set_operation' => sub {
  my @views = grep { /^CREATE OR REPLACE VIEW device_ip_resolved AS/ } @statements;
  is(scalar @views, 1, 'one view statement');
  like($views[0], qr/^CREATE OR REPLACE VIEW device_ip_resolved AS\s+SELECT d\.ip, d\.alias FROM device_ip d\s+WHERE d\.vrf = '' OR device_ip_vrf_row_resolves\(d\.ip, d\.alias, d\.vrf\)$/,
    'default rows as recorded, named-VRF rows through the function');
  unlike($views[0], qr/\b(?:UNION|GROUP BY|DISTINCT|HAVING|EXISTS)\b|\b(?:min|max|count|array_agg)\(/i,
    'no set operation, grouping, aggregate or inline subquery');
  my $function = position_of((grep { /^CREATE OR REPLACE FUNCTION device_ip_vrf_row_resolves\(/ } @statements)[0]);
  my $view = position_of($views[0]);
  ok(defined $function && $function < $view, 'function created before the view');
};

subtest 'step_104_105__alias_index__covering_index_created_if_not_exists' => sub {
  ok(defined position_of('CREATE INDEX IF NOT EXISTS idx_device_ip_alias_vrf_ip ON device_ip (alias, vrf, ip)'),
    'covering index created if not exists');
};

subtest 'step_104_105__existing_alias_index__left_in_place' => sub {
  ok(!grep({ /DROP INDEX[^;]*\bidx_device_ip_alias\b(?!_)/ } @statements),
    'step 105 does not drop idx_device_ip_alias');
};

subtest 'result_classes__vrf__declared_and_in_primary_key' => sub {
  my %key = (DeviceIp => [qw(ip alias vrf)], Subnet => [qw(net vrf)]);
  foreach my $class (sort keys %key) {
    my $package = "App::Netdisco::DB::Result::$class";
    eval "require $package" or die $@;
    is_deeply([ $package->primary_columns ], $key{$class}, "$class primary key");
    my $info = $package->column_info('vrf');
    is($info->{data_type}, 'text', "$class data_type");
    is($info->{is_nullable}, 0, "$class not nullable");
    is($info->{default_value}, '', "$class default");
  }
};

subtest 'result_class__device_ip_resolved__is_a_view_on_device_ip_resolved' => sub {
  my $package = 'App::Netdisco::DB::Result::DeviceIpResolved';
  eval "require $package" or die $@;
  my $source = $package->result_source_instance;
  is($source->name, 'device_ip_resolved', 'view name');
  ok(!$source->is_virtual, 'a real database view');
  is_deeply([ $source->columns ], [qw(ip alias)], 'columns');
};

subtest 'schema_version__is_105' => sub {
  is($App::Netdisco::DB::VERSION, 105);
};

done_testing;
