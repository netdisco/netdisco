package App::Netdisco::Util::Node;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use NetAddr::MAC;
use App::Netdisco::Util::Permission qw/check_acl_no check_acl_only/;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  check_mac
  is_nbtstatable
  store_arp
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::Node

=head1 DESCRIPTION

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 check_mac( $node, $device?, $port_macs? )

Given a MAC address, perform various sanity checks which need to be done
before writing an ARP/Neighbor entry to the database storage.

Returns false, and might log a debug level message, if the checks fail.

Returns a true value (the MAC address in IEEE format) if these checks pass:

=over 4

=item *

MAC address is well-formed (according to common formats)

=item *

MAC address is not all-zero, broadcast, CLIP, VRRP or HSRP

=back

Optionally pass a Device instance or IP to use in logging.

Optionally pass a cached set of Device port MAC addresses as the third
argument, in which case an additional check is added:

=over 4

=item *

MAC address does not belong to an interface on any known Device

=back

=cut

sub check_mac {
  my ($node, $port_macs, $device) = @_;
  return 0 if !$node;

  my $mac = NetAddr::MAC->new(mac => $node);
  my $devip = ($device ? (ref $device ? $device->ip : $device) : '');
  $port_macs ||= {};

  # incomplete MAC addresses (BayRS frame relay DLCI, etc)
  if (!defined $mac or $mac->errstr) {
      debug sprintf ' [%s] check_mac - mac [%s] malformed - skipping',
        $devip, $node;
      return 0;
  }
  else {
      # lower case, hex, colon delimited, 8-bit groups
      $node = lc $mac->as_ieee;
  }

  # broadcast MAC addresses
  return 0 if $mac->is_broadcast;

  # all-zero MAC addresses
  return 0 if $node eq '00:00:00:00:00:00';

  # CLIP
  return 0 if $node eq '00:00:00:00:00:01';

  # multicast
  if ($mac->is_multicast and not $mac->is_msnlb) {
      debug sprintf ' [%s] check_mac - multicast mac [%s] - skipping',
        $devip, $node;
      return 0;
  }

  # VRRP
  if ($mac->is_vrrp) {
      debug sprintf ' [%s] check_mac - VRRP mac [%s] - skipping',
        $devip, $node;
      return 0;
  }

  # HSRP
  if ($mac->is_hsrp or $mac->is_hsrp2) {
      debug sprintf ' [%s] check_mac - HSRP mac [%s] - skipping',
        $devip, $node;
      return 0;
  }

  # device's own MACs
  if ($port_macs and exists $port_macs->{$node}) {
      debug sprintf ' [%s] check_mac - mac [%s] is device port - skipping',
        $devip, $node;
      return 0;
  }

  return $node;
}

=head2 is_nbtstatable( $ip )

Given an IP address, returns C<true> if Netdisco on this host is permitted by
the local configuration to nbtstat the node.

The configuration items C<nbtstat_no> and C<nbtstat_only> are checked
against the given IP.

Returns false if the host is not permitted to nbtstat the target node.

=cut

sub is_nbtstatable {
  my $ip = shift;

  return if check_acl_no($ip, 'nbtstat_no');

  return unless check_acl_only($ip, 'nbtstat_only');

  return 1;
}

=head2 store_arp( \%host, $now? )

Stores a new entry to the C<node_ip> table with the given MAC, IP (v4 or v6)
and DNS host name. Host details are provided in a Hash ref:

 {
    ip   => '192.0.2.1',
    node => '00:11:22:33:44:55',
    dns  => 'myhost.example.com',
 }

The C<dns> entry is optional. The update will mark old entries for this IP as
no longer C<active>.

Optionally a literal string can be passed in the second argument for the
C<time_last> timestamp, otherwise the current timestamp (C<now()>) is used.

=cut

sub store_arp {
  my ($hash_ref, $now) = @_;
  $now ||= 'now()';
  my $ip   = $hash_ref->{'ip'};
  my $mac  = NetAddr::MAC->new($hash_ref->{'node'});
  my $name = $hash_ref->{'dns'};

  return if !defined $mac or $mac->errstr;

  schema('netdisco')->txn_do(sub {
    my $current = schema('netdisco')->resultset('NodeIp')
      ->search(
        { ip => $ip, -bool => 'active'},
        { columns => [qw/mac ip/] })->update({active => \'false'});

    schema('netdisco')->resultset('NodeIp')
      ->update_or_create(
      {
        mac => $mac->as_ieee,
        ip => $ip,
        dns => $name,
        active => \'true',
        time_last => \$now,
      },
      {
        key => 'primary',
        for => 'update',
      });
  });
}

1;
