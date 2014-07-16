package App::Netdisco::Util::DNS;

use strict;
use warnings;

use Dancer ':script';
use Net::DNS;
use AnyEvent::DNS;
use NetAddr::IP::Lite ':lower';

# AE::DNS::EtcHosts only works for A/AAAA/SRV, but we want PTR.
# this loads+parses /etc/hosts file using AE. dirty hack.
use AnyEvent::Socket 'format_address';
use AnyEvent::DNS::EtcHosts;
AnyEvent::DNS::EtcHosts::_load_hosts_unless(sub{},AE::cv);
no AnyEvent::DNS::EtcHosts; # unimport

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

  my %HOSTS = ();
  $HOSTS{$_} = [ map { [ $_ ? (format_address $_->[0]) : '' ] }
                     @{$AnyEvent::DNS::EtcHosts::HOSTS{$_}} ]
    for keys %AnyEvent::DNS::EtcHosts::HOSTS;

  # Set up the condvar
  my $done = AE::cv;
  $done->begin( sub { shift->send } );

  IP: foreach my $hash_ref (@$ips) {
    my $ip = $hash_ref->{'ip'} || $hash_ref->{'alias'};
    next IP if no_resolve($ip);

    # check /etc/hosts file and short-circuit if found
    foreach my $name (reverse sort keys %HOSTS) {
        if ($HOSTS{$name}->[0]->[0] eq $ip) {
            $hash_ref->{'dns'} = $name;
            next IP;
        }
    }

    $done->begin;
    AnyEvent::DNS::reverse_lookup $ip,
            sub { $hash_ref->{'dns'} = shift; $done->end; };
  }

  # Decrement the cv counter to cancel out the send declaration
  $done->end;

  # Wait for the resolver to perform all resolutions
  $done->recv;
  
  # Remove reference to resolver so that we close sockets
  undef $AnyEvent::DNS::RESOLVER if $AnyEvent::DNS::RESOLVER;

  return $ips;
}

=head2 no_resolve( $ip )

Given an IP address, returns true if excluded from DNS resolution by the
C<dns_no> configuration directive, otherwise returns false.

=cut

sub no_resolve {
    my $ip = shift;

    my $config = setting('dns')->{no} || [];
    return 0 if not scalar @$config;

    my $addr = NetAddr::IP::Lite->new($ip);

    foreach my $item (@$config) {
        my $c_ip = NetAddr::IP::Lite->new($item)
            or next;
        next unless $c_ip->bits == $addr->bits;

        return 1 if ($c_ip->contains($addr));
    }
    return 0;
}

1;

