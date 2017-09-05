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

sub _make_new {
  my ($self, $log, $slot) = @_;
  my $new = (ref $self ? $self : $self->new());
  $new->log($log);
  $new->$_(0) for (qw/done_slot error_slot defer_slot/);
  $new->$slot(1);
  return $new;
}

sub error { (shift)->_make_new(@_, 'error_slot') }
sub done  { (shift)->_make_new(@_, 'done_slot')  }
sub defer { (shift)->_make_new(@_, 'defer_slot') }

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

1;
