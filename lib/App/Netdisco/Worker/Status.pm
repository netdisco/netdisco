package App::Netdisco::Worker::Status;

use strict;
use warnings;

use Moo;
use namespace::clean;

foreach my $slot (qw/
      done_slot
      error_slot
      defer_slot
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

sub done  { return (shift)->new({done_slot  => 1, log => shift}) }
sub error { return (shift)->new({error_slot => 1, log => shift}) }
sub defer { return (shift)->new({defer_slot => 1, log => shift}) }

=head2 is_ok

Returns true if C<done> is true and C<error> and C<defer> have not been set.

=cut

sub is_ok { return ($_[0]->done_slot
  and not $_[0]->error_slot and not $_[0]->defer_slot) }

=head2 not_ok

Returns the logical inversion of C<ok>.

=cut

sub not_ok { return (not $_[0]->is_ok) }

=head2 status

Returns text equivalent of C<done>, C<defer>, or C<error>.

=cut

sub status {
  my $self = shift;
  return (
    $self->done_slot ? 'done'
                     : $self->defer_slot ? 'defer'
                                         : 'error'
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
