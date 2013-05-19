package App::Netdisco::Util::Arpnip;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::DB::ExplicitLocking ':modes';
use App::Netdisco::Util::DNS ':all';
use NetAddr::IP::Lite ':lower';
use Net::MAC;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/ do_arpnip /;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::Arpnip

=head1 DESCRIPTION

Helper subroutine to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 arpnip( $device, $snmp )

Given a Device database object, and a working SNMP connection, connect to a
device and discover its ARP cache for IPv4 and Neighbor cache for IPv6.

=cut

sub do_arpnip {
  my ($device, $snmp) = @_;

  unless ($device->in_storage) {
      debug sprintf ' [%s] arpnip - skipping device not yet discovered', $device->ip;
      return;
  }

  my $port_macs = _get_port_macs($device, $snmp);

  schema('netdisco')->resultset('NodeIp')->txn_do_locked(
    EXCLUSIVE, sub {
      my $arp_count = _add_arps($device, $snmp, $port_macs);
      debug sprintf ' [%s] arpnip - processed %s ARP Cache entries',
        $device->ip, $arp_count;

      my $neigh_count = _add_neighbors($device, $snmp, $port_macs);
      debug sprintf ' [%s] arpnip - processed %s IPv6 Neighbor Cache entries',
        $device->ip, $neigh_count;

      $device->update({last_arpnip => \'now()'});
    });

  schema('netdisco')->resultset('Subnet')
    ->txn_do_locked(EXCLUSIVE, sub { _add_subnets($device, $snmp) });
  # TODO: IPv6 subnets
}

# add arp table to DB
sub _add_arps {
  my ($device, $snmp, $port_macs) = @_;
  my $count = 0;

  # Fetch ARP Cache
  my $at_paddr   = $snmp->at_paddr;
  my $at_netaddr = $snmp->at_netaddr;

  while (my ($arp, $node) = each %$at_paddr) {
      my $ip = $at_netaddr->{$arp};
      next unless defined $ip;
      $count += _check_and_store($device, $port_macs, $node, $ip);
  }

  return $count;
}

# add v6 neighbor cache to db
sub _add_neighbors {
  my ($device, $snmp, $port_macs) = @_;
  my $count = 0;

  # Fetch v6 Neighbor Cache
  my $phys_addr = $snmp->ipv6_n2p_mac;
  my $net_addr  = $snmp->ipv6_n2p_addr;

  while (my ($arp, $node) = each %$phys_addr) {
      my $ip = $net_addr->{$arp};
      next unless defined $ip;
      $count += _check_and_store($device, $port_macs, $node, $ip);
  }

  return $count;
}

# checks any arpnip entry for sanity and adds to DB
sub _check_and_store {
  my ($device, $port_macs, $node, $ip) = @_;
  my $mac = Net::MAC->new(mac => $node, 'die' => 0, verbose => 0);

  # incomplete MAC addresses (BayRS frame relay DLCI, etc)
  if ($mac->get_error) {
      debug sprintf ' [%s] arpnip - mac [%s] malformed - skipping',
        $device->ip, $node;
      return 0;
  }
  else {
      # lower case, hex, colon delimited, 8-bit groups
      $node = lc $mac->as_IEEE;
  }

  # broadcast MAC addresses
  return 0 if $node eq 'ff:ff:ff:ff:ff:ff';

  # CLIP
  return 0 if $node eq '00:00:00:00:00:01';

  # VRRP
  if (index($node, '00:00:5e:00:01:') == 0) {
      debug sprintf ' [%s] arpnip - VRRP mac [%s] - skipping',
        $device->ip, $node;
      return 0;
  }

  # HSRP
  if (index($node, '00:00:0c:07:ac:') == 0) {
      debug sprintf ' [%s] arpnip - HSRP mac [%s] - skipping',
        $device->ip, $node;
      return 0;
  }

  # device's own MACs
  if (exists $port_macs->{$node}) {
      debug sprintf ' [%s] arpnip - mac [%s] is device port - skipping',
        $device->ip, $node;
      return 0;
  }

  debug sprintf ' [%s] arpnip - IP [%s] : mac [%s]',
    $device->ip, $ip, $node;
  _add_arp($node, $ip);

  return 1;
}

# add arp cache entry to the node_ip table
sub _add_arp {
  my ($mac, $ip) = @_;

  schema('netdisco')->resultset('NodeIp')
    ->search({ip => $ip, -bool => 'active'})
    ->update({active => \'false'});

  schema('netdisco')->resultset('NodeIp')
    ->search({mac => $mac, ip => $ip})
    ->update_or_create({
      mac => $mac,
      ip => $ip,
      dns => hostname_from_ip($ip),
      active => \'true',
      time_last => \'now()',
    });
}

# gathers and stores device subnets
sub _add_subnets {
  my ($device, $snmp) = @_;

  my $ip_netmask = $snmp->ip_netmask;
  my $localnet = NetAddr::IP::Lite->new('127.0.0.0/8');

  foreach my $entry (keys %$ip_netmask) {
      my $ip = NetAddr::IP::Lite->new($entry);
      my $addr = $ip->addr;

      next if $addr eq '0.0.0.0';
      next if $ip->within($localnet);
      next if setting('ignore_private_nets') and $ip->is_rfc1918;

      my $netmask = $ip_netmask->{$addr};
      next if $netmask eq '255.255.255.255' or $netmask eq '0.0.0.0';

      my $cidr = NetAddr::IP::Lite->new($addr, $netmask)->network->cidr;
      schema('netdisco')->resultset('Subnet')
        ->update_or_create({net => $cidr, last_discover => \'now()'});

      debug sprintf ' [%s] arpnip - found subnet %s', $device->ip, $cidr;
  }
}

# returns table of MACs used by device's interfaces so that we don't bother to
# macsuck them.
sub _get_port_macs {
  my ($device, $snmp) = @_;
  my $port_macs;

  my $dp_macs = schema('netdisco')->resultset('DevicePort')
    ->search({ mac => { '!=' => undef} });
  while (my $r = $dp_macs->next) {
      $port_macs->{ $r->mac } = $r->ip;
  }

  my $d_macs = schema('netdisco')->resultset('Device')
    ->search({ mac => { '!=' => undef} });
  while (my $r = $d_macs->next) {
      $port_macs->{ $r->mac } = $r->ip;
  }

  return $port_macs;
}

1;
