package App::Netdisco::Util::Node;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use Net::MAC;
use App::Netdisco::Util::Permission 'check_acl';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  check_mac
  check_node_no
  check_node_only
  is_nbtstatable
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::Node

=head1 DESCRIPTION

A set of helper subroutines to support parts of the Netdisco application.

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

=head2 check_node_no( $ip, $setting_name )

Given the IP address of a node, returns true if the configuration setting
C<$setting_name> matches that device, else returns false. If the setting
is undefined or empty, then C<check_node_no> also returns false.

 print "rejected!" if check_node_no($ip, 'nbtstat_no');

There are several options for what C<$setting_name> can contain:

=over 4

=item *

Hostname, IP address, IP prefix

=item *

IP address range, using a hyphen and no whitespace

=item *

Regular Expression in YAML format which will match the node DNS name, e.g.:

 - !!perl/regexp ^sep0.*$

=back

To simply match all nodes, use "C<any>" or IP Prefix "C<0.0.0.0/0>". All
regular expressions are anchored (that is, they must match the whole string).
To match no nodes we recommend an entry of "C<localhost>" in the setting.

=cut

sub check_node_no {
  my ($ip, $setting_name) = @_;

  my $config = setting($setting_name) || [];
  return 0 if not scalar @$config;

  return check_acl($ip, $config);
}

=head2 check_node_only( $ip, $setting_name )

Given the IP address of a node, returns true if the configuration setting
C<$setting_name> matches that node, else returns false. If the setting
is undefined or empty, then C<check_node_only> also returns true.

 print "rejected!" unless check_node_only($ip, 'nbtstat_only');

There are several options for what C<$setting_name> can contain:

=over 4

=item *

Hostname, IP address, IP prefix

=item *

IP address range, using a hyphen and no whitespace

=item *

Regular Expression in YAML format which will match the node DNS name, e.g.:

 - !!perl/regexp ^sep0.*$

=back

To simply match all nodes, use "C<any>" or IP Prefix "C<0.0.0.0/0>". All
regular expressions are anchored (that is, they must match the whole string).
To match no nodes we recommend an entry of "C<localhost>" in the setting.

=cut

sub check_node_only {
  my ($ip, $setting_name) = @_;

  my $config = setting($setting_name) || [];
  return 1 if not scalar @$config;

  return check_acl($ip, $config);
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

  return _bail_msg("is_nbtstatable: node matched nbtstat_no")
    if check_node_no($ip, 'nbtstat_no');

  return _bail_msg("is_nbtstatable: node failed to match nbtstat_only")
    unless check_node_only($ip, 'nbtstat_only');

  return 1;
}

1;
