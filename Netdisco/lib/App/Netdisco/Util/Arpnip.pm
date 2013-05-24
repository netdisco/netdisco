package App::Netdisco::Util::Arpnip;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::DB::ExplicitLocking ':modes';
use App::Netdisco::Util::PortMAC ':all';
use App::Netdisco::Util::DNS ':all';
use NetAddr::IP::Lite ':lower';
use Time::HiRes 'gettimeofday';
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

=head2 do_arpnip( $device, $snmp )

Given a Device database object, and a working SNMP connection, connect to a
device and discover its ARP cache for IPv4 and Neighbor cache for IPv6.

Will also discover subnets in use on the device and update the Subnets table.

=cut

sub do_arpnip {
  my ($device, $snmp) = @_;

  unless ($device->in_storage) {
      debug sprintf ' [%s] arpnip - skipping device not yet discovered', $device->ip;
      return;
  }

  my (@v4, @v6);
  my $port_macs = get_port_macs($device);

  # get v4 arp table
  push @v4, _get_arps($device, $port_macs, $snmp->at_paddr, $snmp->at_netaddr);
  # get v6 neighbor cache
  push @v6, _get_arps($device, $port_macs, $snmp->ipv6_n2p_mac, $snmp->ipv6_n2p_addr);

  # get directly connected networks
  my @subnets = _gather_subnets($device, $snmp);
  # TODO: IPv6 subnets

  # would be possible just to use now() on updated records, but by using this
  # same value for them all, we _can_ if we want add a job at the end to
  # select and do something with the updated set (no reason to yet, though)
  my $now = join '.', gettimeofday;

  # update node_ip with ARP and Neighbor Cache entries
  # TODO: ORDER BY ... FOR UPDATE will allow us to avoid the table lock
  schema('netdisco')->resultset('NodeIp')->txn_do_locked(
    EXCLUSIVE, sub {
      _store_arp(@$_, $now) for @v4;
      debug sprintf ' [%s] arpnip - processed %s ARP Cache entries',
        $device->ip, scalar @v4;

      _store_arp(@$_, $now) for @v6;
      debug sprintf ' [%s] arpnip - processed %s IPv6 Neighbor Cache entries',
        $device->ip, scalar @v6;

      $device->update({last_arpnip => \"to_timestamp($now)"});
    });

  # update subnets with new networks
  foreach my $cidr (@subnets) {
      schema('netdisco')->txn_do(sub {
          schema('netdisco')->resultset('Subnet')->update_or_create(
          {
            net => $cidr,
            last_discover => \"to_timestamp($now)",
          },
          # update_or_create doesn't seem to lock the row
          { for => 'update'});
      });
  }
  debug sprintf ' [%s] arpnip - processed %s Subnet entries',
    $device->ip, scalar @subnets;
}

# get an arp table (v4 or v6)
sub _get_arps {
  my ($device, $port_macs, $paddr, $netaddr) = @_;
  my @arps = ();

  while (my ($arp, $node) = each %$paddr) {
      my $ip = $netaddr->{$arp};
      next unless defined $ip;
      my $arp = _check_arp($device, $port_macs, $node, $ip);
      push @arps, [@$arp, hostname_from_ip($ip)]
        if ref [] eq ref $arp;
  }

  return @arps;
}

# checks any arpnip entry for sanity and adds to DB
sub _check_arp {
  my ($device, $port_macs, $node, $ip) = @_;
  my $mac = Net::MAC->new(mac => $node, 'die' => 0, verbose => 0);

  # incomplete MAC addresses (BayRS frame relay DLCI, etc)
  if ($mac->get_error) {
      debug sprintf ' [%s] arpnip - mac [%s] malformed - skipping',
        $device->ip, $node;
      return;
  }
  else {
      # lower case, hex, colon delimited, 8-bit groups
      $node = lc $mac->as_IEEE;
  }

  # broadcast MAC addresses
  return if $node eq 'ff:ff:ff:ff:ff:ff';

  # CLIP
  return if $node eq '00:00:00:00:00:01';

  # VRRP
  if (index($node, '00:00:5e:00:01:') == 0) {
      debug sprintf ' [%s] arpnip - VRRP mac [%s] - skipping',
        $device->ip, $node;
      return;
  }

  # HSRP
  if (index($node, '00:00:0c:07:ac:') == 0) {
      debug sprintf ' [%s] arpnip - HSRP mac [%s] - skipping',
        $device->ip, $node;
      return;
  }

  # device's own MACs
  if (exists $port_macs->{$node}) {
      debug sprintf ' [%s] arpnip - mac [%s] is device port - skipping',
        $device->ip, $node;
      return;
  }

  return [$node, $ip];
}

# add arp cache entry to the node_ip table
sub _store_arp {
  my ($mac, $ip, $name, $now) = @_;

  schema('netdisco')->resultset('NodeIp')
    ->search({ip => $ip, -bool => 'active'})
    ->update({active => \'false'});

  schema('netdisco')->resultset('NodeIp')
    ->search({mac => $mac, ip => $ip})
    ->update_or_create({
      mac => $mac,
      ip => $ip,
      dns => $name,
      active => \'true',
      time_last => \"to_timestamp($now)",
    });
}

# gathers device subnets
sub _gather_subnets {
  my ($device, $snmp) = @_;
  my @subnets = ();

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

      debug sprintf ' [%s] arpnip - found subnet %s', $device->ip, $cidr;
      push @subnets, $cidr;
  }

  return @subnets;
}

1;
