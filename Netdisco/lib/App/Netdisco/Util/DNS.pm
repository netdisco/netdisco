package App::Netdisco::Util::DNS;

use strict;
use warnings FATAL => 'all';

use Net::DNS;
use AnyEvent::DNS;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  hostname_from_ip hostnames_resolve_async ipv4_from_hostname
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
  return unless $ip;

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

=head2 ipv4_from_hostname( $name )

Given a host name will return the first IPv4 address.

Returns C<undef> if no A record exists for the name.

=cut

sub ipv4_from_hostname {
  my $name = shift;
  return unless $name;

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

=head2 hostnames_resolve_async( $ips )

This method uses a fully asynchronous and high-performance pure-perl stub
resolver C<AnyEvent::DNS>.

Given a reference to an array of hashes will resolve the C<IPv4> or C<IPv6>
address in the C<ip> or C<alias> key of each hash into its hostname which
will be inserted in the C<dns> key of the hash.  The resolver does also
forward-lookups to verify that the resolved hostnames point to the
address.

Returns the supplied reference to an array of hashes with dns values for
addresses which resolved.

=cut

sub hostnames_resolve_async {
  my $ips = shift;

  my $resolver = AnyEvent::DNS->new();
    
  # Set up the condvar
  my $done = AE::cv;
  $done->begin( sub { shift->send } );

  foreach my $hash_ref (@$ips) {
    my $ip = $hash_ref->{'ip'} || $hash_ref->{'alias'};
    $done->begin;
    AnyEvent::DNS::reverse_verify $ip,
            sub { $hash_ref->{'dns'} = shift; $done->end; };
  }

  # Decrement the cv counter to cancel out the send declaration
  $done->end;

  # Wait for the resolver to perform all resolutions
  $done->recv;

  return $ips;
}

1;

