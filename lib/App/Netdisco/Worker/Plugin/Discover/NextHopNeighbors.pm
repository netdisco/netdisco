package App::Netdisco::Worker::Plugin::Discover::NextHopNeighbors;
use Dancer ':syntax';

use App::Netdisco::Worker::Plugin;
use App::Netdisco::Transport::SNMP;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device qw/get_device is_discoverable/;
use App::Netdisco::Util::Permission 'acl_matches';
use App::Netdisco::JobQueue 'jq_insert';
use NetAddr::IP;

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  return unless $device->in_storage and ($device->has_layer(3)
                                         or acl_matches($device, 'force_arpnip')
                                         or acl_matches($device, 'ignore_layers'));

  if (acl_matches($device, 'skip_neighbors')
      or not setting('discover_neighbors')
      or not setting('discover_routed_neighbors')) {

      return Status->info(
        sprintf ' [%s] neigh - routed neighbor discovery is disabled on this device',
        $device->ip);
  }

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  my $ospf_peers   = $snmp->ospf_peers || {};
  my $ospf_routers = $snmp->ospf_peer_id || {};
  my $isis_peers   = $snmp->isis_peers || {};
  my $bgp_peers    = $snmp->bgp_peer_addr || {};
  my $eigrp_peers  = $snmp->eigrp_peers || {};

  return Status->info(" [$device] neigh - no BGP, OSPF, IS-IS, or EIGRP peers")
    unless ((scalar values %$ospf_peers) or (scalar values %$ospf_routers)
            or (scalar values %$bgp_peers) or (scalar values %$eigrp_peers)
            or (scalar values %$isis_peers));

  foreach my $ip ((values %$ospf_peers), (values %$ospf_routers),
                  (values %$bgp_peers), (values %$eigrp_peers),
                  (values %$isis_peers)) {

      push @{ vars->{'next_hops'} }, $ip;
  }

  return Status->info(sprintf " [%s] neigh - found %s routed peers.",
    $device, scalar @{ vars->{'next_hops'} });
});

register_worker({ phase => 'store' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  my $nh = vars->{'next_hops'};
  return unless ref [] eq ref $nh and scalar @$nh;

  my $count = 0;
  foreach my $host (@$nh) {
      my $ip = NetAddr::IP->new($host);
      if (not $ip or $ip->addr eq '0.0.0.0'
          or acl_matches($ip->addr, 'group:__LOOPBACK_ADDRESSES__')) {

          debug sprintf ' [%s] neigh - skipping routed peer %s is not valid',
            $device, $host;
          next;
      }

      my $peer = get_device($ip);
      next if $peer->in_storage or not is_discoverable($peer);
      next if vars->{'queued'}->{$peer->ip};

      jq_insert({
        device => $peer->ip,
        action => 'discover',
        subaction => 'with-nodes',
      });

      $count++;
      vars->{'queued'}->{$peer->ip} += 1;
      debug sprintf ' [%s] neigh - queued %s for discovery (peer)', $device, $peer->ip;
  }

  return Status->info(" [$device] neigh - $count peers added to queue.");
});

true;
