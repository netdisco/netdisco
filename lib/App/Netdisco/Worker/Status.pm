package App::Netdisco::Worker::Status;

use strict;
use warnings;

use Dancer qw/:moose :syntax !error !info/;

use Moo;
use namespace::clean;

has 'status' => (
  is => 'rw',
  default => undef,
);

has [qw/log phase/] => (
  is => 'rw',
  default => '',
);

=head1 INTRODUCTION

The status can be:

=over 4

=item * C<done>

success and this could be the outcome of the action

=item * C<info>

success and notable but not the main goal of the action

=item * C<defer>

failed to connect, should increment defer counters

=item * C<error>

had a problem and was unsuccessful

=item * C<()>

skipped the worker for some reason but not fatal

=back

=head1 METHODS

=head2 done, info, defer, error

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

sub done  { shift->_make_new('done', @_)  }
sub info  { shift->_make_new('info', @_)  }
sub defer { shift->_make_new('defer', @_) }
sub error { shift->_make_new('error', @_) }

=head2 is_ok

Returns true if status is C<done>.

=cut

sub is_ok { return $_[0]->status eq 'done' }

=head2 not_ok

Returns true if status is C<error>, C<defer>, or C<info>.

=cut

sub not_ok { return (not $_[0]->is_ok) }

=head2 level

A numeric constant for the status, to allow comparison.

=cut

sub level {
  my $self = shift;
  return (($self->status eq 'done')  ? 4
        : ($self->status eq 'info')  ? 3
        : ($self->status eq 'defer') ? 2 : 1);
}

1;
