package App::Netdisco::Daemon::Worker::Poller::Device;

use Dancer qw/:moose :syntax :script/;

use App::Netdisco::Util::SNMP 'snmp_connect';
use App::Netdisco::Util::Device qw/get_device is_discoverable/;
use App::Netdisco::Core::Discover ':all';
use App::Netdisco::Daemon::Util ':all';
use App::Netdisco::JobQueue qw/jq_queued jq_insert/;

use Dancer::Plugin::DBIC 'schema';
use NetAddr::IP::Lite ':lower';

use Role::Tiny;
use namespace::clean;

# queue a discover job for all devices known to Netdisco
sub discoverall {
  my ($self, $job) = @_;

  my %queued = map {$_ => 1} jq_queued('discover');
  my @devices = schema('netdisco')->resultset('Device')
    ->get_column('ip')->all;
  my @filtered_devices = grep {!exists $queued{$_}} @devices;

  jq_insert([
      map {{
          device => $_,
          action => 'discover',
          username => $job->username,
          userip => $job->userip,
      }} (@filtered_devices)
  ]);

  return job_done("Queued discover job for all devices");
}

# run a discover job for one device, and its *new* neighbors
sub discover {
  my ($self, $job) = @_;

  my $host = NetAddr::IP::Lite->new($job->device);
  my $device = get_device($host->addr);

  if ($device->ip eq '0.0.0.0') {
      return job_error("discover failed: no device param (need -d ?)");
  }

  if ($device->in_storage
      and $device->vendor and $device->vendor eq 'netdisco') {
      return job_done("discover skipped: $host is pseudo-device");
  }

  unless (is_discoverable($device->ip)) {
      return job_defer("discover deferred: $host is not discoverable");
  }

  my $snmp = snmp_connect($device);
  if (!defined $snmp) {
      return job_error("discover failed: could not SNMP connect to $host");
  }

  $device = set_canonical_ip($device, $snmp);
  store_device($device, $snmp);
  store_interfaces($device, $snmp);
  store_wireless($device, $snmp);
  store_vlans($device, $snmp);
  store_power($device, $snmp);
  store_modules($device, $snmp) if setting('store_modules');
  discover_new_neighbors($device, $snmp);

  # if requested, and the device has not yet been arpniped/macsucked, queue now
  if ($device->in_storage and $job->subaction and $job->subaction eq 'with-nodes') {
      if (!defined $device->last_macsuck) {
          jq_insert({
              device => $device->ip,
              action => 'macsuck',
              username => $job->username,
              userip => $job->userip,
          });
      }

      if (!defined $device->last_arpnip) {
          jq_insert({
              device => $device->ip,
              action => 'arpnip',
              username => $job->username,
              userip => $job->userip,
          });
      }
  }

  return job_done("Ended discover for ". $host->addr);
}

1;
