package App::Netdisco::Backend::Job;

use App::Netdisco::Util::Device 'get_device';

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

# $job->device is always a DBIC row
around BUILDARGS => sub {
  my ( $orig, $class, @args ) = @_;
  my $params = $args[0] or return $class->$orig(@args);

  if ((ref {} eq ref $params) and ref $params->{device}) {
    $params->{device} = get_device( $params->{device} );
  }

  return $class->$orig(@args);
};

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
