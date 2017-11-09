package App::Netdisco::Backend::Job;

use Dancer qw/:moose :syntax !error/;
use aliased 'App::Netdisco::Worker::Status';

use Moo;
use namespace::clean;

foreach my $slot (qw/
      job
      entered
      started
      finished
      device
      port
      action
      subaction
      status
      username
      userip
      log

      _current_phase
      _last_namespace
      _last_priority
    /) {

  has $slot => (
    is => 'rw',
  );
}

has '_statuslist' => (
  is => 'rw',
  default => sub { [] },
);

=head1 METHODS

=head2 summary

An attempt to make a meaningful written statement about the job.

=cut

sub summary {
  my $job = shift;
  return join ' ',
    $job->action,
    ($job->device || ''),
    ($job->port || '');
}

=head2 finalise_status

Find the best status and log it into the job's C<status> and C<log> slots.

The process is to track back from the last worker, ignoring user workers, and
find the best status (out of done, defer, error) within the last phase run.

=cut

sub finalise_status {
  my $job = shift;
  # use DDP; p $job->_statuslist;

  # fallback
  $job->status('error');
  $job->log('failed to report from any worker!');

  my $phase = undef;
  my $max_level = Status->error()->level;

  foreach my $status (reverse @{ $job->_statuslist }) {
    next unless $status->phase 
      and $status->phase =~ m/^(?:check|early|main)$/;

    $phase ||= $status->phase;
    last if $status->phase ne $phase;

    if ($status->level > $max_level) {
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
    next unless $status->phase and $status->phase eq 'check';
    return true if $status->is_ok;
  }
  return false;
}

=head2 namespace_passed( \%workerconf )

Returns true when, for the namespace specified in the given configuration, a
worker of a higher priority level has already succeeded.

=cut

sub namespace_passed {
  my ($job, $workerconf) = @_;

  if ($job->_last_namespace) {
    foreach my $status (@{ $job->_statuslist }) {
      next unless ($status->phase and $status->phase eq $workerconf->{phase})
              and ($workerconf->{namespace} eq $job->_last_namespace)
              and ($workerconf->{priority} < $job->_last_priority);
      return true if $status->is_ok;
    }
  }

  $job->_last_namespace( $workerconf->{namespace} );
  $job->_last_priority( $workerconf->{priority} );
  return false;
}

=head2 enter_phase( $phase )

Pass the name of the phase being entered.

=cut

sub enter_phase {
  my ($job, $phase) = @_;

  $job->_current_phase( $phase );
  debug "=> running workers for phase: $phase";

  $job->_last_namespace( undef );
  $job->_last_priority( undef );
}

=head2 add_status

Passed an L<App::Netdisco::Worker::Status> will add it to this job's internal
status cache. Phase slot of the Status will be set to the current phase.

=cut

sub add_status {
  my ($job, $status) = @_;
  return unless ref $status eq 'App::Netdisco::Worker::Status';
  $status->phase( $job->_current_phase );
  push @{ $job->_statuslist }, $status;
  debug $status->log if $status->log;
}

=head1 ADDITIONAL COLUMNS

=head2 id

Alias for the C<job> column.

=cut

sub id { (shift)->job }

=head2 extra

Alias for the C<subaction> column.

=cut

sub extra { (shift)->subaction }

true;
