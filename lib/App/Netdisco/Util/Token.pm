package App::Netdisco::Util::Token;

use strict;
use warnings;

use Crypt::URandom ();

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/ random_token /;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::Token

=head1 DESCRIPTION

Mints session and API authentication secrets.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 random_token

Returns a 64 character lowercase hexadecimal string from L<Crypt::URandom>,
a different value on every call.

=cut

sub random_token {
  return unpack 'H*', Crypt::URandom::urandom(32);
}

1;
