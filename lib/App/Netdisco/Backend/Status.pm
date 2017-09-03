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

1;
