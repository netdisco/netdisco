#!/usr/bin/env perl

# step_mode picks the path each schema step runs on: strict from the baseline
# on, tolerant below it and for --redeploy-all, forced only for the one step
# named by --force-step. The database paths themselves are tested in the
# database harness, since xt stays free of PostgreSQL.

use strict;
use warnings;

use Test::More 0.88;

use App::Netdisco::DB::SchemaVersioned;
use App::Netdisco::DB::StepFile qw(parse_step_file step_file_path);

*step_mode = \&App::Netdisco::DB::SchemaVersioned::step_mode;

subtest 'baseline__is_version_38' => sub {
  is($App::Netdisco::DB::SchemaVersioned::BASELINE, 38);
};
subtest 'step_mode__below_baseline__tolerant' => sub {
  is(step_mode(1, {}), 'tolerant'); is(step_mode(37, {}), 'tolerant');
};
subtest 'step_mode__baseline_and_above__strict' => sub {
  is(step_mode(38, {}), 'strict'); is(step_mode(101, {}), 'strict');
};
subtest 'step_mode__redeploy_all__tolerant_everywhere' => sub {
  is(step_mode(90, { redeploy_all => 1 }), 'tolerant');
};
subtest 'step_mode__force_step__forced_for_that_step_only' => sub {
  is(step_mode(57, { force_step => 57 }), 'forced');
  is(step_mode(58, { force_step => 57 }), 'strict');
};
subtest 'step_mode__no_options__strict_at_baseline' => sub {
  is(step_mode(38), 'strict');
};

my $share = 'share/schema_versions';
sub squash { my $sql = lc shift; $sql =~ s/\s+//g; return $sql }
sub step_statements { return parse_step_file(step_file_path($share, shift))->{statements} }
sub has_statement {
  my ($wanted, $statements) = @_;
  return scalar grep { squash($_) eq squash($wanted) } @$statements;
}

subtest 'step_101__schema_step_forced_ddl__matches_runner' => sub {
  ok(has_statement($App::Netdisco::DB::SchemaVersioned::SCHEMA_STEP_FORCED_DDL, step_statements(101)), 'same definition');
};
subtest 'step_101__port_sortkey__matches_98_99_body' => sub {
  my ($want) = grep { m/port_sortkey/ } @{ step_statements(98) };
  ok($want, 'found the 98-99 function');
  ok(has_statement($want, step_statements(101)), 'same function');
};
subtest 'step_101__index_repair__has_11_drops_23_creates_and_spares_mac_ip' => sub {
  my @statements = @{ step_statements(101) };
  is(scalar(grep { /^DROP INDEX IF EXISTS /i } @statements), 11);
  is(scalar(grep { /^CREATE INDEX IF NOT EXISTS idx_/i } @statements), 23);
  ok(!(grep { /device_port_idx_mac_ip/ } @statements), 'hand-made index untouched');
};
subtest 'step_101__ssid_repair__reuses_the_57_58_deletes_and_key' => sub {
  my @guard = grep { /device_port_ssid/ } @{ step_statements(57) };
  my @deletes = grep { /^DELETE FROM device_port_ssid/i } @guard;
  is(scalar @deletes, 2);
  my @repair = @{ step_statements(101) };
  my $position_of = sub {
    my $wanted = shift;
    my ($index) = grep { squash($repair[$_]) eq squash($wanted) } 0 .. $#repair;
    ok(defined $index, 'present: ' . substr($wanted, 0, 60));
    return $index // -1;
  };
  my @delete_positions = map { $position_of->($_) } @deletes;
  my @not_null_positions = map {
    $position_of->("ALTER TABLE device_port_ssid ALTER COLUMN $_ SET NOT NULL")
  } qw(ip port bssid);
  my $drop_position = $position_of->('ALTER TABLE device_port_ssid DROP CONSTRAINT IF EXISTS device_port_ssid_pkey');
  my ($key) = grep { /ADD CONSTRAINT device_port_ssid_pkey/ } @guard;
  my $add_position = $position_of->($key);
  cmp_ok($delete_positions[$_], '<', $not_null_positions[0], 'delete before SET NOT NULL') for 0, 1;
  cmp_ok($delete_positions[1], '>', $delete_positions[0], 'null cleanup before duplicate cleanup');
  cmp_ok($not_null_positions[2], '<', $drop_position, 'SET NOT NULL before key drop');
  cmp_ok($drop_position, '<', $add_position, 'DROP CONSTRAINT before ADD');
};
subtest 'step_101__device_route__is_one_guarded_do_block' => sub {
  my @blocks = grep { /to_regclass\('device_route'\)/ } @{ step_statements(101) };
  is(scalar @blocks, 1);
  like($blocks[0], qr/IF to_regclass.*IF EXISTS \(SELECT 1 FROM device_route\).*RAISE NOTICE.*ELSE\s+DROP TABLE device_route/s);
};
subtest 'schema_version__is_102' => sub {
  open my $fh, '<', 'lib/App/Netdisco/DB.pm' or die "cannot read DB.pm: $!";
  my ($declared) = map { /\$VERSION = (\d+);/ ? $1 : () } <$fh>;
  is($declared, 102);
};

done_testing;
