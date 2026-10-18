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
  forced_step_summary
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
  like($m, qr/netdisco-db-deploy --check/);
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
  like($m, qr/NETDISCO_DB_DEPLOY_ARGS=--check/);
  unlike($m, qr/^\s*netdisco-db-deploy --force-step/m);
  like($m, qr/fix the cause, then restart the container \(no setting needed\)/i);
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
  like(force_already_applied_message(requested => 57, container => 1), qr/remove.*NETDISCO_DB_DEPLOY_ARGS/i);
};

subtest 'tolerant_summary__counts__one_line_pointing_at_check' => sub {
  my $s = tolerant_summary(expected => 63, steps => 21);
  unlike($s, qr/\n./);
  like($s, qr/63/); like($s, qr/21/); like($s, qr/--check/);
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
};

done_testing;
