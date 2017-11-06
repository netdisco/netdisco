package App::Netdisco::Backend::Job;

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
      debug

      _phase
      _namespace
      _priority
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
  $job->log('failed to succeed at any worker!');

  foreach my $status (@{ $self->_statuslist }) {
    next unless $status->phase =~ m/^(?:early|main)$/;
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
  foreach my $status (@{ $self->_statuslist }) {
    next unless $status->phase eq 'check';
    return 1 if $status->is_ok;
  }
  return 0;
}

=head2 namespace_passed( \%workerconf )

Returns true when, for the namespace specified in the passed configuration,
all workers of a higher priority level have succeeded.

=cut

sub namespace_passed {
  my ($job, $workerconf) = @_;

  if (defined $job->_namespace
      and ($workerconf->{phase} eq $job->_phase)
      and ($workerconf->{namespace} eq $job->_namespace)
      and ($workerconf->{priority} != $job->_priority)) {

    foreach my $status (@{ $self->_statuslist }) {
      next unless ($status->phase eq $job->_phase)
              and ($staus->namespace eq $job->_namespace)
              and ($status->priority == $job->_priority);
      return 1 if $status->is_ok;
    }
  }

  $job->_phase( $workerconf->{phase} );
  $job->_namespace( $workerconf->{namespace} );
  $job->_priority( $workerconf->{priority} );
  return 0;
}

=head2 add_status

Passed an L<App::Netdisco::Worker::Status> will add it to this job's internal
store.

=cut

sub add_status {
  my ($job, $status) = @_;
  return unless ref $status eq 'App::Netdisco::Worker::Status';
  push @{ $self->_statuslist }, $status;
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

1;
