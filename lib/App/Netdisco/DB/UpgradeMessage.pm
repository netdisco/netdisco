package App::Netdisco::DB::UpgradeMessage;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw(
  @EXPECTED_SQLSTATES is_expected_sqlstate strict_failure_message
  force_refusal_message force_already_applied_message tolerant_summary
  unexpected_error_message forced_step_summary
);

our @EXPECTED_SQLSTATES = qw/42P07 42701 42703 42704 42P01 42P16 42601 42883/;
my %EXPECTED = map { $_ => 1 } @EXPECTED_SQLSTATES;

sub is_expected_sqlstate {
  my $state = shift;
  return (defined $state and $EXPECTED{$state}) ? 1 : 0;
}

sub _indent { my $text = shift // ''; $text =~ s/^/    /mg; return $text }

# A container user cannot run a command, so the same action becomes a setting.
sub _action {
  my ($container, $arguments) = @_;
  return $container
    ? "Set NETDISCO_DB_DEPLOY_ARGS=$arguments in the container's environment, then restart the container."
    : "    netdisco-db-deploy $arguments";
}

sub _force_line {
  return 'Forcing skips the failing statements in that step, stamps the new '
    . 'version, and writes a row to the schema_step_forced table so the skip is recorded.';
}

sub strict_failure_message {
  my %arg = @_;
  my ($database, $container) = @arg{qw/database container/};
  return join "\n",
    "The database upgrade stopped at step $arg{from}, in $arg{file}.",
    '',
    'This statement failed:',
    '',
    _indent($arg{statement}),
    '',
    'PostgreSQL said:',
    '',
    _indent($arg{error}),
    '',
    'Nothing from this step was applied, so your data is as it was before the upgrade.',
    '',
    'Before trying anything below, make a backup:',
    '',
    "    pg_dump -Fc $database > netdisco-backup.dump",
    '',
    ($container
      ? 'Fix the cause, then restart the container (no setting needed).'
      : 'Fix the cause, then run netdisco-db-deploy again:'),
    '',
    ($container ? () : ('    netdisco-db-deploy', '')),
    ($container ? 'To see where things stand without changing anything:' : 'To see where things stand without changing anything, run:'),
    '',
    _action($container, '--check'),
    '',
    'If you cannot fix the cause and want to carry on anyway, you can force this step. '
      . _force_line() . ($container ? '' : ' Run:'),
    '',
    _action($container, "--force-step $arg{from}"),
    '',
    ($container ? 'Remove the setting again after the upgrade has finished.' : ()),
    '';
}

sub force_refusal_message {
  my %arg = @_;
  return join "\n",
    "Cannot force step $arg{requested}: steps are applied in order, and step $arg{next_pending} has not been applied yet.",
    '',
    "Force step $arg{next_pending} instead, if you mean to skip it" . ($arg{container} ? '.' : ':'),
    '',
    _action($arg{container}, "--force-step $arg{next_pending}"),
    '';
}

sub force_already_applied_message {
  my %arg = @_;
  my $removal = $arg{container}
    ? 'Remove --force-step from NETDISCO_DB_DEPLOY_ARGS and restart the container.'
    : 'Run netdisco-db-deploy again without --force-step.';
  return join "\n",
    "Step $arg{requested} has already been applied, so there is nothing to force.",
    '',
    $removal,
    '';
}

sub tolerant_summary {
  my %arg = @_;
  return "Expected errors on $arg{expected} statements across $arg{steps} older steps were ignored; "
    . 'run netdisco-db-deploy --check to see the result.';
}

sub forced_step_summary {
  my %arg = @_;
  return "Step $arg{from} was forced: $arg{skipped} failing statements were skipped "
    . 'and recorded in the schema_step_forced table.';
}

sub unexpected_error_message {
  my %arg = @_;
  return join "\n",
    "An older upgrade step, $arg{file}, hit an error that is not one of the usual harmless ones (SQLSTATE $arg{state}).",
    '',
    'This statement failed:',
    '',
    _indent($arg{statement}),
    '',
    'PostgreSQL said:',
    '',
    _indent($arg{error}),
    '';
}

1;
