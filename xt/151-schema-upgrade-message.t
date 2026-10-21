#!/usr/bin/env perl

# App::Netdisco::DB::UpgradeMessage holds the text a stopped schema upgrade
# prints. The reader may have little sysadmin skill, so every message must say
# what happened and give the exact next step: a command to copy when running
# natively, or the NETDISCO_DB_DEPLOY_ARGS setting when in a container, where
# the user cannot run the command.

use strict;
use warnings;

use Test::More 0.88;

use App::Netdisco::DB::UpgradeMessage qw(
  is_expected_sqlstate strict_failure_message force_refusal_message
  force_already_applied_message tolerant_summary unexpected_error_message
  forced_step_summary forced_step_clean_message
);

subtest 'is_expected_sqlstate__listed_and_unlisted__classified' => sub {
  ok(is_expected_sqlstate($_), "expected $_") for qw/42P07 42701 42703 42704 42P01 42P16 42601 42883/;
  ok(!is_expected_sqlstate($_), 'unexpected ' . ($_ // 'undef')) for qw/23505 23502 40P01/, undef;
};

subtest 'strict_failure_message__native__gives_every_way_forward' => sub {
  my $m = strict_failure_message(file => 'App-Netdisco-DB-57-58-PostgreSQL.sql', from => 57,
    statement => 'ALTER TABLE x ADD PRIMARY KEY (a)', error => 'could not create unique index',
    database => 'netdisco', container => 0);
  like($m, qr/App-Netdisco-DB-57-58-PostgreSQL\.sql/);
  like($m, qr/ALTER TABLE x ADD PRIMARY KEY \(a\)/);
  like($m, qr/could not create unique index/);
  like($m, qr/nothing from this step was applied/i);
  like($m, qr/^\s*netdisco-db-deploy --force-step 57\s*$/m);
  like($m, qr/recorded/i);
  like($m, qr/skips the failing statements in that step/);
  unlike($m, qr/--check/);
  like($m, qr/before it in this run were applied and stay applied/);
  like($m, qr/pg_dump .*netdisco/);
  unlike($m, qr/NETDISCO_DB_DEPLOY_ARGS/);
  like($m, qr/fix the cause, then run netdisco-db-deploy again/i);
  like($m, qr/^\s*netdisco-db-deploy\s*$/m);
  unlike($m, qr/Run this command/);
};

subtest 'strict_failure_message__container__names_the_setting_not_a_command' => sub {
  my $m = strict_failure_message(file => 'f', from => 57, statement => 's', error => 'e',
    database => 'netdisco', container => 1);
  like($m, qr/NETDISCO_DB_DEPLOY_ARGS=--force-step 57/);
  unlike($m, qr/--check/);
  like($m, qr/dbInit\.deployArgs: "--force-step 57"/);
  unlike($m, qr/restart the container/i);
  unlike($m, qr/^\s*pg_dump/m);
  unlike($m, qr/^\s*netdisco-db-deploy --force-step/m);
  like($m, qr/fix the cause, then start the upgrade again: rerun your docker compose up command/i);
  like($m, qr/run helm upgrade/);
};

subtest 'strict_failure_message__undef_statement_and_error__no_warnings' => sub {
  my @warnings;
  local $SIG{__WARN__} = sub { push @warnings, @_ };
  strict_failure_message(file => 'f', from => 1, database => 'd', container => 0);
  is_deeply(\@warnings, []);
};

subtest 'force_refusal_message__future_step__names_next_pending' => sub {
  like(force_refusal_message(requested => 60, next_pending => 57, container => 0), qr/--force-step 57/);
};

subtest 'force_already_applied_message__container__says_remove_the_setting' => sub {
  my $m = force_already_applied_message(requested => 57, container => 1);
  like($m, qr/remove.*NETDISCO_DB_DEPLOY_ARGS/i);
  unlike($m, qr/restart/i);
};
subtest 'force_already_applied_message__native__says_drop_it_next_time_not_rerun' => sub {
  my $m = force_already_applied_message(requested => 57, container => 0);
  like($m, qr/carries on/);
  like($m, qr/leave --force-step off next time/);
  unlike($m, qr/again/i);
};

subtest 'tolerant_summary__counts__one_line_pointing_at_check' => sub {
  my $s = tolerant_summary(expected => 63, steps => 21);
  unlike($s, qr/\n./);
  like($s, qr/63/); like($s, qr/21/); like($s, qr/--check/);
};

subtest 'tolerant_summary__unexpected_only__points_at_check' => sub {
  my $s = tolerant_summary(expected => 0, steps => 0, unexpected => 1);
  unlike($s, qr/\n./);
  like($s, qr/^An error in an older step is shown above; run netdisco-db-deploy --check to see the result\.$/);
  like(tolerant_summary(expected => 0, steps => 0, unexpected => 2), qr/^2 errors in older steps are shown above/);
};
subtest 'tolerant_summary__expected_and_unexpected__both_counted' => sub {
  my $s = tolerant_summary(expected => 63, steps => 21, unexpected => 2);
  like($s, qr/^Expected errors on 63 statements across 21 older steps were ignored, and 2 other errors are shown above; run netdisco-db-deploy --check/);
};
subtest 'unexpected_error_message__details__names_file_state_and_statement' => sub {
  my $m = unexpected_error_message(file => 'f.sql', statement => 'DROP TABLE y',
    state => '23505', error => 'duplicate key');
  like($m, qr/f\.sql/); like($m, qr/23505/); like($m, qr/DROP TABLE y/); like($m, qr/duplicate key/);
};

subtest 'forced_step_summary__step_and_count__one_line_naming_the_record' => sub {
  my $s = forced_step_summary(from => 57, skipped => 3);
  unlike($s, qr/\n./);
  like($s, qr/\b57\b/); like($s, qr/\b3\b/); like($s, qr/schema_step_forced/);
  unlike($s, qr/older/);
  like($s, qr/run netdisco-db-deploy --check to see what is missing/);
};

subtest 'forced_step_clean_message__step__says_nothing_was_skipped_or_recorded' => sub {
  my $s = forced_step_clean_message(from => 57);
  unlike($s, qr/\n./);
  like($s, qr/^Step 57 applied without errors, so nothing was skipped or recorded\.$/);
};
subtest 'forced_step_summary__container__gives_the_setting_not_the_command' => sub {
  my $s = forced_step_summary(from => 57, skipped => 3, container => 1);
  like($s, qr/schema_step_forced table\. To see what is missing, set NETDISCO_DB_DEPLOY_ARGS=--check in \.env/);
  like($s, qr/dbInit\.deployArgs: "--check"/);
  unlike($s, qr/run netdisco-db-deploy/);
};

subtest 'tolerant_summary__container__gives_the_setting_not_the_command' => sub {
  my $s = tolerant_summary(expected => 63, steps => 21, container => 1);
  like($s, qr/were ignored\. To see the result, set NETDISCO_DB_DEPLOY_ARGS=--check in \.env/);
  unlike($s, qr/run netdisco-db-deploy/);
};

done_testing;
