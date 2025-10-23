package App::Netdisco::Util::Node;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use NetAddr::MAC;
use App::Netdisco::Util::Permission qw/acl_matches acl_matches_only/;

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
  my ($node, $device, $port_macs) = @_;
  return 0 if !$node;

  my $mac = NetAddr::MAC->new(mac => ($node || ''));
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

  return if acl_matches($ip, 'nbtstat_no');

  return unless acl_matches_only($ip, 'nbtstat_only');

  return 1;
}

=head2 store_arp( \%host, $now?, $device_ip )

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
C<time_last> timestamp, otherwise the current timestamp (C<LOCALTIMESTAMP>) is used.

On which L3 devices an arp entry was found is tracked in the
C<seen_on_router_first> and C<seen_on_router_last> fields of the C<node_ip>.
They contain a timestamp for the time window each router this entry was ever
found on.

=cut

sub store_arp {
  my ($hash_ref, $now, $device_ip) = @_;
  $now ||= 'LOCALTIMESTAMP';
  my $ip   = $hash_ref->{'ip'};
  my $mac  = NetAddr::MAC->new(mac => ($hash_ref->{'node'} || $hash_ref->{'mac'} || ''));
  my $vrf  = $hash_ref->{'vrf'} || '';
  my $name = $hash_ref->{'dns'};

  return if !defined $mac or $mac->errstr;
  warning sprintf 'store_arp - deprecated usage, should be store_arp($hash_ref, $now, $device_ip)' unless $device_ip;
  debug sprintf 'store_arp - device %s mac %s ip %s vrf "%s"', $device_ip // "n/a", $mac->as_ieee, $ip, $vrf;

  schema(vars->{'tenant'})->txn_do(sub {
    schema(vars->{'tenant'})->resultset('NodeIp')
      ->search(
        { ip => $ip, -bool => 'active'},
        { columns => [qw/mac ip vrf/] })->update({active => \'false'});

    my $row = schema(vars->{'tenant'})->resultset('NodeIp')
      ->update_or_new(
      {
        mac => $mac->as_ieee,
        ip => $ip,
        vrf => $vrf,
        dns => $name,
        active => \'true',
        time_last => \$now
      },
      {
        key => 'primary',
        for => 'update',
      });

    if (! $row->in_storage) {
      $row->set_column(time_first => \$now);

      if ($device_ip) {
        # init the tracking, setting the first+last stamps to now
        $row->set_column(seen_on_router_first => \[qq{jsonb_build_object(?::text, $now)}, $device_ip ]);
        $row->set_column(seen_on_router_last =>  \[qq{jsonb_build_object(?::text, $now)}, $device_ip ]);
      }

      $row->insert;
    }
    else {
      if ($device_ip) {
        # set or update the last seen for this router to now
        $row->set_column(seen_on_router_last => \[qq{
          jsonb_set(seen_on_router_last, ?, to_jsonb($now))} => (qq!{$device_ip}!) ]);

        # add the first seen for this router if first time seen, else no-op
        $row->set_column(seen_on_router_first => \[qq{
          CASE WHEN (seen_on_router_first->?) IS NOT NULL
            THEN seen_on_router_first
            ELSE jsonb_set(seen_on_router_first, ?, to_jsonb($now)) 
          END } => ($device_ip, qq!{$device_ip}!) ]);

        $row->update;
      }
    }

  });
}

1;
