#!/usr/bin/env perl

# The argument and --force-step rules of netdisco-db-deploy. The step loop
# itself needs PostgreSQL, so it is tested in the database harness.

use strict;
use warnings;

use Test::More 0.88;
use Try::Tiny;

use App::Netdisco::DB::Deploy qw(parse_args validate_force_step run_deploy);

sub exception (&) { my $code = shift; return try { $code->(); undef } catch { $_ } }

subtest 'parse_args__no_args__plain_upgrade' => sub {
  is_deeply(parse_args([]), { redeploy_all => 0, force_step => undef, check => 0 });
};
subtest 'parse_args__force_step__integer_required' => sub {
  is(parse_args(['--force-step', '57'])->{force_step}, 57);
  like(exception { parse_args(['--force-step', 'x']) }, qr/--force-step/);
};
subtest 'parse_args__force_step_equals_form__accepted' => sub {
  is(parse_args(['--force-step=57'])->{force_step}, 57);
};
subtest 'parse_args__force_step_without_value__refused' => sub {
  like(exception { parse_args(['--force-step']) }, qr/--force-step/);
};
subtest 'parse_args__force_step_twice__refused_with_usage' => sub {
  like(exception { parse_args(['--force-step', '57', '--force-step', '58']) },
    qr/--force-step.*\n.*Usage/s);
};
subtest 'parse_args__force_step_not_plain_digits__refused' => sub {
  like(exception { parse_args(['--force-step', "57\n"]) }, qr/--force-step/);
  like(exception { parse_args(['--force-step', '+57']) }, qr/--force-step/);
};
subtest 'parse_args__check_with_other_option__refused' => sub {
  like(exception { parse_args(['--check', '--redeploy-all']) }, qr/--check/);
  like(exception { parse_args(['--force-step', '57', '--check']) }, qr/--check/);
};
subtest 'parse_args__check_alone__accepted' => sub {
  is(parse_args(['--check'])->{check}, 1);
};
subtest 'parse_args__force_step_with_redeploy_all__refused' => sub {
  like(exception { parse_args(['--redeploy-all', '--force-step', '57']) }, qr/--force-step/);
};
subtest 'parse_args__redeploy_all_not_first__still_honored' => sub {
  is(parse_args(['--redeploy-all'])->{redeploy_all}, 1);
  like(exception { parse_args(['extra', '--redeploy-all']) }, qr/extra/);
};
subtest 'parse_args__unknown_option__refused_with_usage' => sub {
  like(exception { parse_args(['--bogus']) }, qr/bogus.*\n.*Usage/s);
};
subtest 'parse_args__argv__left_untouched' => sub {
  my @argv = ('--force-step', '57');
  parse_args(\@argv);
  is_deeply(\@argv, ['--force-step', '57']);
};
subtest 'validate_force_step__next_pending__run' => sub {
  is(validate_force_step(57, 57), 'run');
};
subtest 'validate_force_step__force_step_already_applied__warns_and_continues' => sub {
  is(validate_force_step(57, 60), 'already_applied');
};
subtest 'validate_force_step__future_step__refused' => sub {
  is(validate_force_step(60, 57), 'future');
};

# A stand-in for App::Netdisco::DB with canned step results, so the loop's
# exit codes and output can be tested without PostgreSQL.
{
  package FakeStorage;
  sub new { bless {}, shift }
  sub dbh_do { die "no device table\n" }
  sub disconnect { 1 }
  sub sqlt_type { 'PostgreSQL' }
  sub dbh { { pg_db => 'fakedb' } }
  sub txn_scope_guard { undef }

  package FakeSchema;
  sub new { my ($class, %arg) = @_; bless { calls => [], missing => {}, %arg }, $class }
  sub storage { FakeStorage->new }
  sub get_db_version { $_[0]{version} }
  sub schema_version { $_[0]{target} }
  sub upgrade_directory { '/fake/schema_versions' }
  sub ddl_filename {
    my ($self, $type, $to, $dir, $from) = @_;
    return $self->{missing}{$from} ? '/nonexistent/step.sql' : __FILE__;
  }
  sub upgrade_single_step {
    my ($self, $from, $to, $mode) = @_;
    push @{ $self->{calls} }, [$from, $mode];
    return $self->{results}{$from};
  }
}

sub ok_step { my %extra = @_; return { ok => 1, expected => 0, unexpected => [], skipped => [],
  failed => undef, file => 'step.sql', %extra } }

sub run_captured {
  my ($schema, $options) = @_;
  my ($out, $err) = ('', '');
  open my $out_fh, '>', \$out; open my $err_fh, '>', \$err;
  local *STDOUT = $out_fh; local *STDERR = $err_fh;
  my $exit = run_deploy($schema, $options);
  return ($exit, $out, $err);
}

subtest 'run_deploy__all_steps_ok__exit_0_and_strict_from_baseline' => sub {
  my $schema = FakeSchema->new(version => 37, target => 39,
    results => { 37 => ok_step(), 38 => ok_step() });
  my ($exit) = run_captured($schema, {});
  is($exit, 0);
  is_deeply($schema->{calls}, [[37, 'tolerant'], [38, 'strict']]);
};
subtest 'run_deploy__step_returns_undef__exit_1' => sub {
  my $schema = FakeSchema->new(version => 50, target => 52, results => { 50 => undef });
  my ($exit, undef, $err) = run_captured($schema, {});
  is($exit, 1);
  like($err, qr/stopped at step 50/);
};
subtest 'run_deploy__missing_step_file__exit_1_one_message_no_call' => sub {
  my $schema = FakeSchema->new(version => 50, target => 52, missing => { 50 => 1 });
  my ($exit, undef, $err) = run_captured($schema, {});
  is($exit, 1);
  my @mentions = ($err =~ m/stopped at step 50/g);
  is(scalar @mentions, 1);
  is_deeply($schema->{calls}, []);
};
subtest 'run_deploy__strict_step_fails__exit_1_with_strict_message' => sub {
  my $failed = { statement => 'INSERT INTO x VALUES (1)', state => '42P01', error => 'no x' };
  my $schema = FakeSchema->new(version => 50, target => 52,
    results => { 50 => ok_step(ok => 0, failed => $failed), 51 => ok_step() });
  my ($exit, $out, $err) = run_captured($schema, {});
  is($exit, 1);
  like($err, qr/--force-step 50/);
  like($err, qr/pg_dump -Fc fakedb/);
  is_deeply($schema->{calls}, [[50, 'strict']]);
  is($out, '');
};
subtest 'run_deploy__force_step_past_latest__exit_2' => sub {
  my $schema = FakeSchema->new(version => 101, target => 101);
  my ($exit, undef, $err) = run_captured($schema, { force_step => 101 });
  is($exit, 2);
  like($err, qr/already at version 101, the latest/);
};
subtest 'run_deploy__force_step_future__exit_2_naming_next_pending' => sub {
  my $schema = FakeSchema->new(version => 50, target => 60);
  my ($exit, undef, $err) = run_captured($schema, { force_step => 55 });
  is($exit, 2);
  like($err, qr/--force-step 50/);
  is_deeply($schema->{calls}, []);
};
subtest 'run_deploy__leftover_force_step__warns_and_exit_0' => sub {
  my $schema = FakeSchema->new(version => 60, target => 61, results => { 60 => ok_step() });
  my ($exit, undef, $err) = run_captured($schema, { force_step => 57 });
  is($exit, 0);
  like($err, qr/Step 57 has already been applied/);
  is_deeply($schema->{calls}, [[60, 'strict']]);
};
subtest 'run_deploy__tolerant_expected_errors__one_summary_line' => sub {
  my $schema = FakeSchema->new(version => 10, target => 12,
    results => { 10 => ok_step(expected => 2), 11 => ok_step(expected => 1) });
  my ($exit, $out) = run_captured($schema, {});
  is($exit, 0);
  like($out, qr/^Expected errors on 3 statements across 2 older steps/);
  is(scalar(() = $out =~ m/\n/g), 1);
};
subtest 'run_deploy__quiet__suppresses_the_summary' => sub {
  my $schema = FakeSchema->new(version => 10, target => 11,
    results => { 10 => ok_step(expected => 2) });
  my ($exit, $out, $err) = run_captured($schema, { quiet => 1 });
  is($exit, 0);
  is($out, ''); is($err, '');
};
subtest 'run_deploy__forced_step__reported_as_forced_not_older' => sub {
  my $skipped = [ { statement => 'INSERT INTO x VALUES (1)', state => '42P01', error => 'no x' },
                  { statement => 'SELECT 1/0', state => '22012', error => 'division by zero' } ];
  my $schema = FakeSchema->new(version => 57, target => 58,
    results => { 57 => ok_step(expected => 1, unexpected => [ $skipped->[1] ], skipped => $skipped) });
  my ($exit, $out, $err) = run_captured($schema, { force_step => 57 });
  is($exit, 0);
  is_deeply($schema->{calls}, [[57, 'forced']]);
  like($err, qr/Step 57 was forced: 2 failing statements/);
  unlike($out . $err, qr/older/);
};

done_testing;
