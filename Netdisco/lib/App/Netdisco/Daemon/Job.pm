package App::Netdisco::Daemon::Job;

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
    /) {

  has $slot => (
    is => 'rw',
  );
}

=head1 METHODS

=head2 summary

An attempt to make a meaningful statement about the job.

=cut

sub summary {
    my $job = shift;
    return join ' ',
      $job->action,
      ($job->device || ''),
      ($job->port || '');
#      ($job->subaction ? (q{'}. $job->subaction .q{'}) : '');
}

=head1 ADDITIONAL COLUMNS

=head2 extra

Alias for the C<subaction> column.

=cut

sub extra { (shift)->subaction }

1;
