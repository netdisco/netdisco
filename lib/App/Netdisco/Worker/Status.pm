package App::Netdisco::Worker::Status;

use strict;
use warnings;

use Moo;
use namespace::clean;

foreach my $slot (qw/
      done
      error
      defer
    /) {

  has $slot => (
    is => 'rw',
    default => 0,
  );
}

has 'log' => (
  is => 'rw',
  default => '',
);

=head1 METHODS

=head2 done, error, defer

Shorthand for new() with setting param, accepts log as arg.

=cut

sub done  { return (shift)->new({done  => 1, log => shift}) }
sub error { return (shift)->new({error => 1, log => shift}) }
sub defer { return (shift)->new({defer => 1, log => shift}) }

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

Updates an L<App::Netdisco::Backend::Job> with status and log.

=cut

sub update_job {
  my $self = shift;
  my $job = shift or return;
  $job->status( $self->status );
  $job->log( $self->log );
}

1;
