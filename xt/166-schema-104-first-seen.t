#!/usr/bin/env perl

# Step 103-104 adds first_seen to device_ip and device_port. No upsert writes
# it, so it keeps the time the row was first inserted.

use strict;
use warnings;

use Test::More 0.88;

use App::Netdisco::DB::StepFile qw(parse_step_file);
use App::Netdisco::DB;

my $step = parse_step_file('share/schema_versions/App-Netdisco-DB-103-104-PostgreSQL.sql');
my @alters = grep { /^ALTER TABLE/ } @{ $step->{statements} };
my @add_columns = grep { /ADD COLUMN/ } @alters;

subtest 'step_103_104__parses__four_statements_in_one_transaction' => sub {
  is($step->{no_transaction}, 0, 'runs in a transaction');
  is(scalar @alters, 4, 'four ALTER statements');
  is(scalar @{ $step->{statements} }, 5, 'plus the SET LOCAL line');
};

# On 9.6 a default in ADD COLUMN rewrites the table under an exclusive lock,
# so the column is added bare and the default set afterwards.
subtest 'step_103_104__add_column__if_not_exists_and_no_default' => sub {
  is(scalar @add_columns, 2, 'one ADD COLUMN per table');
  foreach my $statement (@add_columns) {
    like($statement, qr/ADD COLUMN IF NOT EXISTS first_seen timestamp\z/, $statement);
    unlike($statement, qr/DEFAULT/i, 'no default in ADD COLUMN');
  }
};

subtest 'step_103_104__set_default__localtimestamp_on_both_tables' => sub {
  foreach my $table (qw(device_ip device_port)) {
    ok((grep { $_ eq "ALTER TABLE $table ALTER COLUMN first_seen SET DEFAULT LOCALTIMESTAMP" } @alters),
      "$table default set");
    ok((grep { /^ALTER TABLE $table ADD COLUMN/ } @alters), "$table column added");
  }
};

subtest 'result_classes__first_seen__declared_on_device_ip_and_device_port' => sub {
  foreach my $class (qw(DeviceIp DevicePort)) {
    my $package = "App::Netdisco::DB::Result::$class";
    eval "require $package" or die $@;
    my $info = $package->column_info('first_seen');
    is($info->{data_type}, 'timestamp', "$class data_type");
    ok($info->{is_nullable}, "$class nullable");
    is(${ $info->{default_value} }, 'LOCALTIMESTAMP', "$class default");
  }
};

subtest 'schema_version__is_104' => sub {
  is($App::Netdisco::DB::VERSION, 104);
};

done_testing;
