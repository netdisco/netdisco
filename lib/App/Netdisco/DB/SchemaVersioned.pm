package App::Netdisco::DB::SchemaVersioned;

use strict;
use warnings;

use base 'DBIx::Class::Schema::Versioned';

use Try::Tiny;
use DBIx::Class::Carp;
use File::Basename ();
use JSON::PP ();

use App::Netdisco::DB::StepFile qw(parse_step_file legacy_statements);
use App::Netdisco::DB::UpgradeMessage qw(is_expected_sqlstate);

our $BASELINE = 38;

our $SCHEMA_STEP_FORCED_DDL = 'CREATE TABLE IF NOT EXISTS schema_step_forced ('
  . 'step integer NOT NULL, '
  . 'forced_at timestamp NOT NULL DEFAULT LOCALTIMESTAMP, '
  . 'failed_count integer NOT NULL, '
  . "failures jsonb NOT NULL DEFAULT '[]')";

sub step_mode {
  my ($from, $options) = @_;
  $options ||= {};
  return 'forced'
    if defined $options->{force_step} and $options->{force_step} == $from;
  return 'tolerant' if $options->{redeploy_all};
  return $from < $BASELINE ? 'tolerant' : 'strict';
}

my %VALID_STEP_MODES = map { $_ => 1 } qw/strict tolerant forced/;

# DBIC's own upgrade() calls this with two arguments, hence the default mode.
sub upgrade_single_step {
  my ($self, $from, $to, $mode) = @_;
  $mode ||= step_mode($from, {});
  die "upgrade_single_step was given mode '$mode' for step $from;"
    . " pass one of strict, tolerant or forced, or leave it out to let step_mode choose\n"
    unless $VALID_STEP_MODES{$mode};

  if ($from eq $to) {
    carp 'Upgrade not necessary';
    return;
  }

  my $step_file = $self->ddl_filename(
    $self->storage->sqlt_type, $to, $self->upgrade_directory, $from);
  unless (-f $step_file) {
    carp "Upgrade not possible, no upgrade file found ($step_file), please create one";
    return;
  }

  # Netdisco's configured connections already set auto_savepoint; this covers
  # one made without it, whose first nested rollback would otherwise abort
  # the outer txn_scope_guard of an ND2_DB_ROLLBACK run.
  $self->storage->auto_savepoint(1) if $ENV{ND2_DB_ROLLBACK};

  return $self->_strict_step($step_file, $to) if $mode eq 'strict';
  return $self->_tolerant_step($step_file, $to) if $mode eq 'tolerant';
  return $self->_tolerant_step($step_file, $to,
    sub { $self->record_forced_step($from, shift) }, $from >= $BASELINE);
}

sub _new_step_result {
  my $step_file = shift;
  return { ok => 0, expected => 0, unexpected => [], skipped => [],
           failed => undef, file => File::Basename::basename($step_file) };
}

# DBD::Pg's state and errstr must be read before DBIC rolls back: afterwards
# they describe the rollback, and the rethrown text carries no SQLSTATE.
sub _do_capturing_failure {
  my ($self, $statement, $failure_ref) = @_;
  my $dbh = $self->storage->dbh;
  try { $dbh->do($statement) }
  catch {
    $$failure_ref = { statement => $statement, state => $dbh->state,
                      error => ($dbh->errstr // "$_") };
    die $_;
  };
}

sub _strict_step {
  my ($self, $step_file, $to) = @_;
  my $result = _new_step_result($step_file);
  my $parsed = parse_step_file($step_file);
  my $failure;

  my $apply_and_stamp = sub {
    $self->_do_capturing_failure($_, \$failure) for @{ $parsed->{statements} };
    $self->_set_db_version({version => $to});
  };

  try {
    $parsed->{no_transaction}
      ? $self->_in_quiet_session($apply_and_stamp)
      : $self->_in_quiet_transaction($apply_and_stamp);
    $result->{ok} = 1;
  }
  catch {
    $result->{failed} = $failure
      || { statement => undef, state => undef, error => "$_" };
  };
  return $result;
}

# Whole file first, so steps with dollar-quoted bodies replay cleanly; then,
# only if that failed, per statement. The old split breaks DO blocks apart,
# so it is kept only for the steps that always ran that way.
sub _tolerant_step {
  my ($self, $step_file, $to, $before_stamp, $split_as_parsed) = @_;
  my $strict_result = $self->_strict_step($step_file, $to);
  return $strict_result if $strict_result->{ok};

  my $parsed = parse_step_file($step_file);
  my $no_transaction = $parsed->{no_transaction};
  my $statements = $split_as_parsed
    ? $parsed->{statements} : legacy_statements($step_file);
  my $result = _new_step_result($step_file);
  my $replay = sub {
    $self->_replay_statement($_, $result, $no_transaction) for @$statements;
  };
  $no_transaction ? $self->_in_quiet_session($replay) : $replay->();

  $self->_in_quiet_transaction(sub {
    $before_stamp->($result->{skipped}) if $before_stamp and @{ $result->{skipped} };
    $self->_set_db_version({version => $to});
  });
  $result->{ok} = 1;
  return $result;
}

# PostgreSQL refuses statements such as CREATE INDEX CONCURRENTLY inside a
# transaction, so a no-transaction step replays them bare.
sub _replay_statement {
  my ($self, $statement, $result, $no_transaction) = @_;
  my $failure;
  my $run = sub { $self->_do_capturing_failure($statement, \$failure) };
  try { $no_transaction ? $run->() : $self->_in_quiet_transaction($run) }
  catch { _tally_tolerated_failure($result, $failure, $statement, $_) };
}

# The IF [NOT] EXISTS forms in old steps raise NOTICE "skipping" lines that
# read as faults. A step can still set it back to notice for a NOTICE it
# means the user to see, as 101-102 does.
sub _in_quiet_transaction {
  my ($self, $code) = @_;
  return $self->storage->txn_do(sub {
    $self->storage->dbh->do('SET LOCAL client_min_messages = warning');
    return $code->();
  });
}

# SET LOCAL outside a transaction does nothing, so quiet the session instead
# and put the old level back.
sub _in_quiet_session {
  my ($self, $code) = @_;
  my $dbh = $self->storage->dbh;
  my ($previous) = $dbh->selectrow_array('SHOW client_min_messages');
  $dbh->do('SET client_min_messages = warning');
  my $failure;
  try { $code->() } catch { $failure = $_ };
  # Fails only in an aborted ND2_DB_ROLLBACK transaction, whose rollback
  # restores the level anyway.
  try { $dbh->do('SET client_min_messages = ' . $dbh->quote($previous)) };
  die $failure if defined $failure;
}

sub _tally_tolerated_failure {
  my ($result, $failure, $statement, $exception) = @_;
  carp "SQL was: $statement" if $ENV{DBIC_TRACE};
  $failure ||= { statement => $statement, state => undef, error => "$exception" };
  push @{ $result->{skipped} }, $failure;
  if (is_expected_sqlstate($failure->{state})) {
    $result->{expected}++;
    return;
  }
  push @{ $result->{unexpected} }, $failure;
}

sub record_forced_step {
  my ($self, $from, $skipped) = @_;
  $skipped ||= [];
  my $failures_json = JSON::PP->new->canonical->encode([
    map { +{ statement => $_->{statement}, state => $_->{state},
             error => $_->{error} } } @$skipped
  ]);

  $self->storage->dbh_do(sub {
    my (undef, $dbh) = @_;
    $dbh->do($SCHEMA_STEP_FORCED_DDL);
    $dbh->do('INSERT INTO schema_step_forced (step, failed_count, failures)'
      . ' VALUES (?, ?, ?::jsonb)', undef, $from, scalar @$skipped, $failures_json);
  });
}

1;
