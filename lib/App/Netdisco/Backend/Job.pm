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

      _last_phase
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

=cut

sub finalise_status {
  my $job = shift;
  my $max_level = Status->error()->level;

  # fallback
  $job->status('error');
  $job->log('failed to report from any worker!');

  foreach my $status (@{ $job->_statuslist }) {
    if ($status->level >= $max_level) {
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
  foreach my $status (@{ $job->_statuslist }) {
    return true if $status->is_ok;
  }
  return false;
}

=head2 namespace_passed( \%workerconf )

Returns true when, for the namespace specified in the passed configuration,
all workers of a higher priority level have succeeded.

=cut

sub namespace_passed {
  my ($job, $workerconf) = @_;

  if ($job->_last_namespace) {
    foreach my $status (@{ $job->_statuslist }) {
      next unless ($workerconf->{phase} eq $job->_last_phase)
              and ($workerconf->{namespace} eq $job->_last_namespace)
              and ($workerconf->{priority} != $job->_last_priority);
      return true if $status->is_ok;
    }
  }

  # reset the internal status cache when the phase changes
  $job->_statuslist([]) if $job->_last_phase
    and $job->_last_phase ne $workerconf->{phase};

  $job->_last_phase( $workerconf->{phase} );
  $job->_last_namespace( $workerconf->{namespace} );
  $job->_last_priority( $workerconf->{priority} );
  return false;
}

=head2 add_status

Passed an L<App::Netdisco::Worker::Status> will add it to this job's internal
status cache.

=cut

sub add_status {
  my ($job, $status) = @_;
  return unless ref $status eq 'App::Netdisco::Worker::Status';
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
