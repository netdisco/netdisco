package App::Netdisco::Worker::Status;

use strict;
use warnings;

use Moo;
use namespace::clean;

has 'status' => (
  is => 'rw',
  default => undef,
  clearer => 1,
);

has 'log' => (
  is => 'rw',
  default => '',
);

=head1 INTRODUCTION

The status can be:

=over 4

=item * C<done>

At C<check> phase, indicates the action may continue. At other phases,
indicates the worker has completed without error or has no work to do.

=item * C<error>

Indicates that there is an error condition. Also used to quit a worker without
side effects that C<done> and C<defer> have.

=item * C<defer>

Quits a worker. If the final recorded outcome for a device is C<defer> several
times in a row, then it may be skipped from further jobs.

=back

=head1 METHODS

=head2 done, error, defer

Shorthand for new() with setting param, accepts log as arg.

=cut

sub _make_new {
  my ($self, $status, $log) = @_;
  die unless $status;
  my $new = (ref $self ? $self : $self->new());
  $new->log($log);
  $new->status($status);
  return $new;
}

sub error { (shift)->_make_new('error', @_) }
sub done  { (shift)->_make_new('done', @_)  }
sub defer { (shift)->_make_new('defer', @_) }

=head2 is_ok

Returns true if status is C<done>.

=cut

sub is_ok { return $_[0]->status eq 'done' }

=head2 not_ok

Returns true if status is C<error> or C<defer>.

=cut

sub not_ok { return (not $_[0]->is_ok) }

1;
