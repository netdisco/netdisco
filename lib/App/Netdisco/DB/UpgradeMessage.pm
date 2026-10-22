package App::Netdisco::DB::UpgradeMessage;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw(
  @EXPECTED_SQLSTATES is_expected_sqlstate strict_failure_message
  force_refusal_message force_already_applied_message tolerant_summary
  unexpected_error_message forced_step_summary forced_step_clean_message
);

our @EXPECTED_SQLSTATES = qw/42P07 42701 42703 42704 42P01 42P16 42601 42883/;
my %EXPECTED = map { $_ => 1 } @EXPECTED_SQLSTATES;

sub is_expected_sqlstate {
  my $state = shift;
  return (defined $state and $EXPECTED{$state}) ? 1 : 0;
}

sub _indent { my $text = shift // ''; $text =~ s/^/    /mg; return $text }

# Restarting the db-init container alone starts neither backend nor web, and
# helm runs its db-init job only on install or upgrade.
my $CONTAINER_RERUN = 'start the upgrade again: rerun your docker compose up command,'
  . ' which reruns netdisco-db-init, or run helm upgrade, which reruns the db-init job.';

# A container user cannot run a command, so the same action becomes a setting.
sub _action {
  my ($container, $arguments) = @_;
  return $container
    ? "Set NETDISCO_DB_DEPLOY_ARGS=$arguments in .env for docker compose,"
      . qq{ or dbInit.deployArgs: "$arguments" in your helm values. Then $CONTAINER_RERUN}
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
    'Nothing from this step was applied: it was rolled back.'
      . ' Any steps before it in this run were applied and stay applied.',
    '',
    ($container
      ? ("Before trying anything below, back up the $database database with pg_dump,"
          . ' run from wherever the database server can be reached.')
      : ('Before trying anything below, make a backup:', '',
         "    pg_dump -Fc $database > netdisco-backup.dump")),
    '',
    ($container
      ? "Fix the cause, then $CONTAINER_RERUN No setting is needed."
      : 'Fix the cause, then run netdisco-db-deploy again:'),
    '',
    ($container ? () : ('    netdisco-db-deploy', '')),
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
    ? 'The upgrade carries on without it. Remove --force-step from'
      . ' NETDISCO_DB_DEPLOY_ARGS (dbInit.deployArgs with helm) before the next start.'
    : 'The upgrade carries on without it; leave --force-step off next time.';
  return join "\n",
    "Step $arg{requested} has already been applied, so there is nothing to force.",
    '',
    $removal,
    '';
}

sub _check_hint {
  my ($container, $purpose) = @_;
  return $container
    ? ". To $purpose, " . lcfirst _action(1, '--check')
    : "; run netdisco-db-deploy --check to $purpose.";
}

sub tolerant_summary {
  my %arg = @_;
  my $unexpected = $arg{unexpected} || 0;
  my $shown = $unexpected == 1 ? 'is shown above' : 'are shown above';
  # under --redeploy-all the erroring step may be the newest, not an older one
  my ($one, $many) = $arg{replayed}
    ? ('a replayed step', 'replayed steps') : ('an older step', 'older steps');
  my $summary = !$arg{expected}
    ? ($unexpected == 1 ? "An error in $one" : "$unexpected errors in $many") . " $shown"
    : "Expected errors on $arg{expected} statements across $arg{steps} $many were ignored"
      . ($unexpected ? ", and $unexpected other " . ($unexpected == 1 ? 'error' : 'errors') . " $shown" : '');
  return $summary . _check_hint($arg{container}, 'see the result');
}

sub forced_step_summary {
  my %arg = @_;
  return "Step $arg{from} was forced: $arg{skipped} failing statements were skipped "
    . 'and recorded in the schema_step_forced table' . _check_hint($arg{container}, 'see what is missing');
}

sub forced_step_clean_message {
  my %arg = @_;
  return "Step $arg{from} applied without errors, so nothing was skipped or recorded.";
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
