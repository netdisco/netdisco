package App::Netdisco::Worker::Plugin::Discover::Neighbors::Routed;
use Dancer ':syntax';

use App::Netdisco::Worker::Plugin;
use App::Netdisco::Transport::SNMP;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device qw/get_device is_discoverable/;
use App::Netdisco::JobQueue 'jq_insert';

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  return unless $device->in_storage and $device->has_layer(3);
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  my $ospf_peers = $snmp->ospf_peers || {};
  my $bgp_peers  = $snmp->bgp_peer_addr || {};

  return Status->info("device $device has no BGP or OSPF peers")
    unless ((scalar values %$ospf_peers) or (scalar values %$bgp_peers));

  foreach my $ip ((values %$ospf_peers), (values %$bgp_peers)) {
    my $peer = get_device($ip);
    next if $peer->in_storage or not is_discoverable($peer);

    jq_insert({
      device => $ip,
      action => 'discover',
      subaction => 'with-nodes',
    });

    debug sprintf ' [%s] queued discovery of routing peer %s', $device, $ip;
  }

  return Status->info(" [$device] Routing peers added to discover queue.");
});

true;
