package App::Netdisco::Worker::Plugin::Arpnip::Nodes;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Node qw/check_mac store_arp/;
use App::Netdisco::Util::FastResolver 'hostnames_resolve_async';
use Dancer::Plugin::DBIC 'schema';
use Time::HiRes 'gettimeofday';

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("arpnip failed: could not SNMP connect to $device");

  # get v4 arp table
  my $v4 = get_arps($device, $snmp->at_paddr, $snmp->at_netaddr);
  # get v6 neighbor cache
  my $v6 = get_arps($device, $snmp->ipv6_n2p_mac, $snmp->ipv6_n2p_addr);

  # would be possible just to use now() on updated records, but by using this
  # same value for them all, we _can_ if we want add a job at the end to
  # select and do something with the updated set (no reason to yet, though)
  my $now = 'to_timestamp('. (join '.', gettimeofday) .')';

  # update node_ip with ARP and Neighbor Cache entries
  store_arp(\%$_, $now) for @$v4;
  debug sprintf ' [%s] arpnip - processed %s ARP Cache entries',
    $device->ip, scalar @$v4;

  store_arp(\%$_, $now) for @$v6;
  debug sprintf ' [%s] arpnip - processed %s IPv6 Neighbor Cache entries',
    $device->ip, scalar @$v6;

  $device->update({last_arpnip => \$now});
  return Status->done("Ended arpnip for $device");
});

# get an arp table (v4 or v6)
sub get_arps {
  my ($device, $paddr, $netaddr) = @_;
  my @arps = ();

  while (my ($arp, $node) = each %$paddr) {
      my $ip = $netaddr->{$arp};
      next unless defined $ip;
      next unless check_mac($node, $device);
      push @arps, {
        node => $node,
        ip   => $ip,
        dns  => undef,
      };
  }

  debug sprintf ' resolving %d ARP entries with max %d outstanding requests',
    scalar @arps, $ENV{'PERL_ANYEVENT_MAX_OUTSTANDING_DNS'};
  my $resolved_ips = hostnames_resolve_async(\@arps);

  return $resolved_ips;
}

true;
