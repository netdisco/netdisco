package App::Netdisco::Util::DNS;

use strict;
use warnings;
use Dancer ':script';

use Net::DNS;
use NetAddr::IP::Lite ':lower';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/hostname_from_ip ipv4_from_hostname/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::DNS

=head1 DESCRIPTION

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 hostname_from_ip( $ip, \%opts? )

Given an IP address (either IPv4 or IPv6), return the canonical hostname.

C<< %opts >> can override the various timeouts available in
L<Net::DNS::Resolver>:

=over 4

=item C<tcp_timeout>: 120 (seconds)

=item C<udp_timeout>: 30 (seconds)

=item C<retry>: 4 (attempts)

=item C<retrans>: 5 (timeout)

=back

Returns C<undef> if no PTR record exists for the IP.

=cut

sub hostname_from_ip {
  my ($ip, $opts) = @_;
  return unless $ip;
  my $ETCHOSTS = setting('dns')->{'ETCHOSTS'};

  # check /etc/hosts file and short-circuit if found
  foreach my $name (reverse sort keys %$ETCHOSTS) {
      if ($ETCHOSTS->{$name}->[0]->[0] eq $ip) {
          return $name;
      }
  }

  my $res = Net::DNS::Resolver->new;
  $res->tcp_timeout($opts->{tcp_timeout} || 120);
  $res->udp_timeout($opts->{udp_timeout} || 30);
  $res->retry($opts->{retry} || 4);
  $res->retrans($opts->{retrans} || 5);
  my $query = $res->search($ip);

  if ($query) {
      foreach my $rr ($query->answer) {
          next unless $rr->type eq "PTR";
          return $rr->ptrdname;
      }
  }

  return undef;
}

=head2 ipv4_from_hostname( $name )

Given a host name will return the first IPv4 address.

Returns C<undef> if no A record exists for the name.

=cut

sub ipv4_from_hostname {
  my $name = shift;
  return unless $name;
  my $ETCHOSTS = setting('dns')->{'ETCHOSTS'};

  # check /etc/hosts file and short-circuit if found
  if (exists $ETCHOSTS->{$name} and $ETCHOSTS->{$name}->[0]->[0]) {
      my $ip = NetAddr::IP::Lite->new($ETCHOSTS->{$name}->[0]->[0]);
      return $ip->addr if $ip and $ip->bits == 32;
  }

  my $res   = Net::DNS::Resolver->new;
  my $query = $res->search($name);

  if ($query) {
      foreach my $rr ($query->answer) {
          next unless $rr->type eq "A";
          return $rr->address;
      }
  }

  return undef;
}

1;
