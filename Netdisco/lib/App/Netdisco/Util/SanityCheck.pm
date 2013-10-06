package App::Netdisco::Util::SanityCheck;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::PortMAC ':all';
use Net::MAC;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/ check_mac /;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::SanityCheck

=head1 DESCRIPTION

Helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 check_mac( $device, $node, $port_macs? )

Given a Device database object and a MAC address, perform various sanity
checks which need to be done before writing an ARP/Neighbor entry to the
database storage.

Returns false, and might log a debug level message, if the checks fail.

Returns a true value if these checks pass:

=over 4

=item *

MAC address is well-formed (according to common formats)

=item *

MAC address is not all-zero, broadcast, CLIP, VRRP or HSRP

=back

Optionally pass a cached set of Device port MAC addresses as the third
argument, in which case an additional check is added:

=over 4

=item *

MAC address does not belong to an interface on any known Device

=back

=cut

sub check_mac {
  my ($device, $node, $port_macs) = @_;
  my $mac = Net::MAC->new(mac => $node, 'die' => 0, verbose => 0);
  $port_macs ||= {};

  # incomplete MAC addresses (BayRS frame relay DLCI, etc)
  if ($mac->get_error) {
      debug sprintf ' [%s] check_mac - mac [%s] malformed - skipping',
        $device->ip, $node;
      return 0;
  }
  else {
      # lower case, hex, colon delimited, 8-bit groups
      $node = lc $mac->as_IEEE;
  }

  # broadcast MAC addresses
  return 0 if $node eq 'ff:ff:ff:ff:ff:ff';

  # all-zero MAC addresses
  return 0 if $node eq '00:00:00:00:00:00';

  # CLIP
  return 0 if $node eq '00:00:00:00:00:01';

  # multicast
  if ($node =~ m/^[0-9a-f](?:1|3|5|7|9|b|d|f):/) {
      debug sprintf ' [%s] check_mac - multicast mac [%s] - skipping',
        $device->ip, $node;
      return 0;
  }

  # VRRP
  if (index($node, '00:00:5e:00:01:') == 0) {
      debug sprintf ' [%s] check_mac - VRRP mac [%s] - skipping',
        $device->ip, $node;
      return 0;
  }

  # HSRP
  if (index($node, '00:00:0c:07:ac:') == 0) {
      debug sprintf ' [%s] check_mac - HSRP mac [%s] - skipping',
        $device->ip, $node;
      return 0;
  }

  # device's own MACs
  if (exists $port_macs->{$node}) {
      debug sprintf ' [%s] check_mac - mac [%s] is device port - skipping',
        $device->ip, $node;
      return 0;
  }

  return 1;
}

1;
