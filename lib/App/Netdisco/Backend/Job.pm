package App::Netdisco::Backend::Job;

use Dancer qw/:moose :syntax !error/;
use aliased 'App::Netdisco::Worker::Status';

use Moo;
use Term::ANSIColor qw(:constants :constants256);
use namespace::clean;

foreach my $slot (qw/
      job
      entered
      started
      finished
      device
      port
      action
      only_namespace
      subaction
      status
      username
      userip
      log
      device_key
      backend
      job_priority
      is_cancelled
      is_offline

      _current_phase
    /) {

  has $slot => (
    is => 'rw',
  );
}

has '_statuslist' => (
  is => 'rw',
  default => sub { [] },
);

sub BUILD {
  my ($job, $args) = @_;

  if ($job->action =~ m/^(\w+)::(\w+)$/i) {
    $job->action($1);
    $job->only_namespace($2);
  }

  if (!defined $job->subaction) {
    $job->subaction('');
  }
}

=head1 METHODS

=head2 display_name

An attempt to make a meaningful written statement about the job.

=cut

sub display_name {
  my $job = shift;
  return join ' ',
    $job->action,
    ($job->device || ''),
    ($job->port || '');
}

=head2 cancel

Log a status and prevent other stages from running.

=cut

sub cancel {
  my ($job, $msg) = @_;
  $msg ||= 'unknown reason for cancelled job';
  $job->is_cancelled(true);
  return Status->error($msg);
}

=head2 best_status

Find the best status so far. The process is to track back from the last worker
and find the highest scoring status, skipping the check phase.

=cut

sub best_status {
  my $job = shift;
  my $cur_level = 0;
  my $cur_status = '';

  foreach my $status (reverse @{ $job->_statuslist }) {
    next if $status->phase
      and $status->phase !~ m/^(?:early|main|store|late)$/;

    if ($status->level >= $cur_level) {
      $cur_level = $status->level;
      $cur_status = $status->status;
    }
  }

  return $cur_status;
}

=head2 finalise_status

Find the best status and log it into the job's C<status> and C<log> slots.

=cut

sub finalise_status {
  my $job = shift;
  # use DDP; p $job->_statuslist;

  # fallback
  $job->status('error');
  $job->log('failed to report from any worker!');

  my $max_level = 0;

  foreach my $status (reverse @{ $job->_statuslist }) {
    next if $status->phase
      and $status->phase !~ m/^(?:check|early|main|user|store|late)$/;

    # done() from check phase should not be the action's done()
    next if $status->phase eq 'check' and $status->is_ok;

    # for done() we want the latest log message
    # for error() (and others) we want the earliest log message

    if (($max_level != Status->done()->level and $status->level >= $max_level)
        or ($status->level > $max_level)) {

      $job->status( $status->status );
      $job->log( $status->log );
      $max_level = $status->level;
    }
  }
}

=head2 check_passed

Returns true if at least one worker during the C<check> phase flagged status
C<done>.

=cut

sub check_passed {
  my $job = shift;
  return true if 0 == scalar @{ $job->_statuslist };

  foreach my $status (@{ $job->_statuslist }) {
    return true if
      (($status->phase eq 'check') and $status->is_ok);
  }
  return false;
}

=head2 enter_phase( $phase )

Pass the name of the phase being entered.

=cut

sub enter_phase {
  my ($job, $phase) = @_;

  $job->_current_phase( $phase );
  debug BRIGHT_CYAN, "//// ", uc($phase), ' \\\\\\\\ ', GREY10, 'phase', RESET;
}

=head2 add_status

Passed an L<App::Netdisco::Worker::Status> will add it to this job's internal
status cache. Phase slot of the Status will be set to the current phase.

=cut

sub add_status {
  my ($job, $status) = @_;
  return unless ref $status eq 'App::Netdisco::Worker::Status';
  $status->phase( $job->_current_phase || '' );
  push @{ $job->_statuslist }, $status;
  if ($status->log) {
      debug GREEN, "\N{LEFTWARDS BLACK ARROW} ", BRIGHT_GREEN, '(', $status->status, ') ', GREEN, $status->log, RESET;
  }
}

=head1 ADDITIONAL COLUMNS

Columns which exist in this class but are not in
L<App::Netdisco::DB::Result::Admin> class.


=head2 id

Alias for the C<job> column.

=cut

sub id { (shift)->job }

=head2 extra

Alias for the C<subaction> column.

=head2 only_namespace

Action command from the user can be an action name or the action name plus one
child namespace in the form: "C<action::child>". This slot stores the C<child>
component of the command so that C<action> is backwards compatible with
Netdisco.

=head2 job_priority

When selecting jobs from the database, some types of job are higher priority -
usually those submitted in the web interface by a user, and those making
changes (writing to) the device. This slot stores a number which is the
priority of the job and is used by L<MCE> when managing its job queue.

=cut

sub extra { (shift)->subaction }

true;
