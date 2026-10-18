package App::Netdisco::DB::Deploy;

use strict;
use warnings;

use Try::Tiny;

use App::Netdisco::DB::SchemaVersioned;
use App::Netdisco::DB::UpgradeMessage qw(
  strict_failure_message force_refusal_message force_already_applied_message
  tolerant_summary unexpected_error_message forced_step_summary
);

use base 'Exporter';
our @EXPORT_OK = qw(parse_args validate_force_step run_deploy);

our $USAGE = "Usage: netdisco-db-deploy [--redeploy-all | --force-step N | --check]\n";

sub _refuse_args { die shift() . "\n" . $USAGE }

sub _read_force_step {
  my ($argument, $remaining) = @_;
  my $value = ($argument =~ m/\A--force-step=(.*)\z/s) ? $1 : shift @$remaining;
  _refuse_args('--force-step needs the number of the step to force, for example --force-step 57.')
    unless defined $value and $value =~ m/\A[0-9]+\z/;
  return 0 + $value;
}

sub _refuse_combinations {
  my $options = shift;
  my $other_option_given = $options->{redeploy_all} || defined $options->{force_step};
  _refuse_args('--check only reads the database, so it cannot be combined with another option.')
    if $options->{check} and $other_option_given;
  _refuse_args('--force-step cannot be combined with --redeploy-all: a replay already tolerates errors in every step.')
    if $options->{redeploy_all} and defined $options->{force_step};
}

sub parse_args {
  my $argv = shift;
  my @remaining = @$argv;
  my %options = (redeploy_all => 0, force_step => undef, check => 0);

  while (defined(my $argument = shift @remaining)) {
    if ($argument eq '--redeploy-all') { $options{redeploy_all} = 1; next }
    if ($argument eq '--check') { $options{check} = 1; next }
    if ($argument =~ m/\A--force-step(?:=|\z)/) {
      _refuse_args('--force-step can be given only once.') if defined $options{force_step};
      $options{force_step} = _read_force_step($argument, \@remaining);
      next;
    }
    _refuse_args("Unknown argument '$argument'.");
  }

  _refuse_combinations(\%options);
  return \%options;
}

sub validate_force_step {
  my ($requested, $db_version) = @_;
  return 'already_applied' if $requested < $db_version;
  return 'future' if $requested > $db_version;
  return 'run';
}

sub _say { my $options = shift; print @_, "\n" unless $options->{quiet} }
sub _warn { my $options = shift; print STDERR @_, "\n" unless $options->{quiet} }

sub _bootstrap_version {
  my ($schema, $options) = @_;

  if ($options->{redeploy_all}) {
    $schema->storage->dbh_do(sub {
      my (undef, $dbh) = @_;
      $dbh->do('DROP TABLE dbix_class_schema_versions');
    });
  }

  # installs the dbix_class_schema_versions table with version "1"
  # which corresponds to an empty schema
  if (not $schema->get_db_version) {
    $schema->install(1);
    $schema->storage->disconnect;
  }

  # test for existing schema at public release version, set v=2 if so
  try {
    $schema->storage->dbh_do(sub {
      my (undef, $dbh) = @_;
      $dbh->selectrow_arrayref('SELECT * FROM device WHERE 0 = 1');
    });
    $schema->_set_db_version({version => 2})
      if $schema->get_db_version == 1;
    $schema->storage->disconnect;
  };
}

# Returns an exit code when the run must stop here, undef to carry on.
sub _check_force_step {
  my ($schema, $options, $db_version, $target_version) = @_;
  my $requested = $options->{force_step};
  return undef unless defined $requested;

  my $verdict = validate_force_step($requested, $db_version);
  my %message_args = (requested => $requested, next_pending => $db_version,
                      container => $options->{container});

  if ($verdict eq 'already_applied') {
    _warn($options, force_already_applied_message(%message_args));
    return undef;
  }
  return _refuse_force_past_latest($requested, $db_version)
    if $db_version >= $target_version;
  return undef if $verdict eq 'run';

  print STDERR force_refusal_message(%message_args), "\n";
  return 2;
}

# force_refusal_message names a next pending step, and here there is none.
sub _refuse_force_past_latest {
  my ($requested, $db_version) = @_;
  print STDERR "Cannot force step $requested: the database is already at version"
    . " $db_version, the latest, so there is no step to force.\n";
  return 2;
}

sub _missing_step_message {
  my ($schema, $from) = @_;
  return sprintf "The database upgrade stopped at step %d: no upgrade file for %d-%d"
    . " was found in %s. Reinstall Netdisco so the file is present, then run"
    . " netdisco-db-deploy again.", $from, $from, $from + 1, $schema->upgrade_directory;
}

sub _report_unexpected {
  my ($options, $step_result) = @_;
  foreach my $failure (@{ $step_result->{unexpected} }) {
    _warn($options, unexpected_error_message(
      file => $step_result->{file}, statement => $failure->{statement},
      state => ($failure->{state} // 'none'), error => $failure->{error}));
  }
}

sub _strict_failure_text {
  my ($schema, $options, $from, $step_result) = @_;
  my $failed = $step_result->{failed} || {};
  return strict_failure_message(
    from => $from, file => $step_result->{file},
    statement => ($failed->{statement} // '(the step as a whole)'),
    error => ($failed->{error} // 'no error text was returned'),
    database => ($schema->storage->dbh->{pg_db} // 'netdisco'),
    container => $options->{container});
}

sub _step_file_exists {
  my ($schema, $from) = @_;
  return -f $schema->ddl_filename(
    $schema->storage->sqlt_type, $from + 1, $schema->upgrade_directory, $from);
}

# Returns the step's result, or undef after printing why the run must stop.
sub _apply_step {
  my ($schema, $options, $from) = @_;
  # checked here because upgrade_single_step only carps and returns undef
  my $step_result = _step_file_exists($schema, $from)
    ? $schema->upgrade_single_step($from, $from + 1,
        App::Netdisco::DB::SchemaVersioned::step_mode($from, $options))
    : undef;
  if (not $step_result) {
    print STDERR _missing_step_message($schema, $from), "\n";
    return undef;
  }
  if (not $step_result->{ok}) {
    print STDERR _strict_failure_text($schema, $options, $from, $step_result), "\n";
    return undef;
  }
  return $step_result;
}

sub _is_forced_step {
  my ($options, $from) = @_;
  return (defined $options->{force_step} and $options->{force_step} == $from);
}

sub _run_steps {
  my ($schema, $options, $db_version, $target_version) = @_;
  my %tally = (expected => 0, steps => 0);

  for (my $from = $db_version; $from < $target_version; $from++) {
    my $step_result = _apply_step($schema, $options, $from);
    return (1, \%tally) unless $step_result;

    if (_is_forced_step($options, $from)) {
      _warn($options, forced_step_summary(
        from => $from, skipped => scalar @{ $step_result->{skipped} || [] }));
      next;
    }
    _report_unexpected($options, $step_result);
    next unless $step_result->{expected};
    $tally{expected} += $step_result->{expected};
    $tally{steps}++;
  }
  return (0, \%tally);
}

sub run_deploy {
  my ($schema, $options) = @_;
  $options ||= {};

  _bootstrap_version($schema, $options);

  # roll everything back if we're testing
  my $txn_guard = $ENV{ND2_DB_ROLLBACK}
    ? $schema->storage->txn_scope_guard : undef;

  # get_db_version is 0 at first deploy
  my $db_version = ($schema->get_db_version || 1);
  my $target_version = $schema->schema_version;

  my $refusal = _check_force_step($schema, $options, $db_version, $target_version);
  return $refusal if defined $refusal;

  my ($exit_code, $tally) = _run_steps($schema, $options, $db_version, $target_version);
  _say($options, tolerant_summary(%$tally))
    if $exit_code == 0 and $tally->{expected};

  undef $txn_guard if $ENV{ND2_DB_ROLLBACK};
  return $exit_code;
}

1;
