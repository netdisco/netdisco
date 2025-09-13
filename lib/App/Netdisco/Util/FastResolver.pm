package App::Netdisco::Util::FastResolver;

use strict;
use warnings;
use Dancer ':script';

use AnyEvent::Loop;
use AnyEvent::DNS;
use App::Netdisco::Util::Permission 'acl_matches';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/hostnames_resolve_async/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::FastResolver

=head1 DESCRIPTION

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 hostnames_resolve_async( \@ips, \@timeouts? )

This method uses a fully asynchronous and high-performance pure-perl stub
resolver C<AnyEvent::DNS>.

Given a reference to an array of hashes will resolve the C<IPv4> or C<IPv6>
address in the C<ip>, C<alias>, or C<device> key of each hash into its
hostname which will be inserted in the C<dns> key of the hash.

Optionally provide a set of timeout values in seconds which is also the
number of resolver attempts. The default is C<< [2,5,5] >>.

Returns the supplied reference to an array of hashes with dns values for
addresses which resolved.

=cut

sub hostnames_resolve_async {
  my ($ips, $timeouts) = @_;
  return [] unless $ips and ref [] eq ref $ips;
  $timeouts ||= [2,5,5];

  my $skip = setting('dns')->{'no'};
  my $ETCHOSTS = setting('dns')->{'ETCHOSTS'};
  AnyEvent::DNS::resolver->timeout(@$timeouts);
  AnyEvent::DNS::resolver->os_config();

  # Set up the condvar
  my $done = AE::cv;
  $done->begin( sub { shift->send } );

  IP: foreach my $hash_ref (@$ips) {
    my $ip = $hash_ref->{'ip'} || $hash_ref->{'alias'} || $hash_ref->{'device'};
    next IP if acl_matches($ip, $skip);

    # check /etc/hosts file and short-circuit if found
    foreach my $name (reverse sort keys %$ETCHOSTS) {
        if ($ETCHOSTS->{$name}->[0]->[0] eq $ip) {
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
  # and allow return to any instance defaults we have changed
  undef $AnyEvent::DNS::RESOLVER if $AnyEvent::DNS::RESOLVER;

  return $ips;
}

1;
