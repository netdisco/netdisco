package App::Netdisco::Backend::Status;

use strict;
use warnings;

use Moo;
use namespace::clean;

foreach my $slot (qw/
      done
      error
      defer
      message
    /) {

  has $slot => (
    is => 'rw',
  );
}

=head1 METHODS

=head2 ok

Returns true if C<done> is true and C<error> and C<defer> have not been set.

=cut

sub ok { return ($_[0]->done and not $_[0]->error and not $_[0]->defer) }

=head2 not_ok

Returns the logical inversion of C<ok>.

=cut

sub not_ok { return (not $_[0]->ok) }

=head2 status

Returns text equivalent of C<done>, C<defer>, or C<error>.

=cut

sub status {
  my $self = shift;
  return (
    $self->done ? 'done'
                : $self->defer ? 'defer'
                               : 'error';
  );
}

=head2 update_job

Updates an L<App::Netdisco::Backend::Job> with status and message.

=cut

sub update_job {
  my $self = shift;
  my $job = shift or return;
  $job->status( $self->status );
  $job->log( $self->message );
}

1;
