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

# On 9.6 a default in ADD COLUMN rewrites the table under an exclusive lock,
# so the column is added bare, then defaulted, backfilled and made NOT NULL.
subtest 'step_104_105__add_column__bare_then_default_backfill_not_null' => sub {
  foreach my $table (qw(device_ip subnets)) {
    my @add = grep { /^ALTER TABLE $table ADD COLUMN/ } @statements;
    is(scalar @add, 1, "$table: one ADD COLUMN");
    is($add[0], "ALTER TABLE $table ADD COLUMN IF NOT EXISTS vrf text", "$table: bare column");
    unlike($add[0], qr/DEFAULT/i, "$table: no default in ADD COLUMN");

    my @order = map { position_of($_) } (
      "ALTER TABLE $table ADD COLUMN IF NOT EXISTS vrf text",
      "ALTER TABLE $table ALTER COLUMN vrf SET DEFAULT ''",
      "UPDATE $table SET vrf = '' WHERE vrf IS NULL",
      "ALTER TABLE $table ALTER COLUMN vrf SET NOT NULL",
    );
    ok((!grep { !defined } @order), "$table: all four statements present");
    is_deeply([ sort { $a <=> $b } grep { defined } @order ], [ grep { defined } @order ],
      "$table: in the required order");
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

subtest 'step_104_105__view__create_or_replace_device_ip_resolved' => sub {
  my @views = grep { /^CREATE OR REPLACE VIEW device_ip_resolved AS/ } @statements;
  is(scalar @views, 1, 'one view statement');
  unlike($views[0], qr/;/, 'no semicolon inside the statement');
  unlike($views[0], qr/min\(/i, 'no min() on inet');
  like($views[0], qr/d\.alias = d\.ip\s+AND NOT EXISTS \(SELECT 1 FROM device_ip x WHERE x\.alias = d\.alias AND x\.vrf = '' AND x\.ip <> d\.ip\)/,
    'own-address branch yields to another device\'s default row');
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
