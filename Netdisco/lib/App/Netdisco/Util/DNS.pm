package App::Netdisco::Util::DNS;

use strict;
use warnings FATAL => 'all';

use Net::DNS;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  hostname_from_ip
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::DNS

=head1 DESCRIPTION

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 hostname_from_ip( $ip )

Given an IP address (either IPv4 or IPv6), return the canonical hostname.

Returns C<undef> if no PTR record exists for the IP.

=cut

sub hostname_from_ip {
  my $ip = shift;

  my $res   = Net::DNS::Resolver->new;
  my $query = $res->search($ip);

  if ($query) {
      foreach my $rr ($query->answer) {
          next unless $rr->type eq "PTR";
          return $rr->ptrdname;
      }
  }

  return undef;
}

1;

