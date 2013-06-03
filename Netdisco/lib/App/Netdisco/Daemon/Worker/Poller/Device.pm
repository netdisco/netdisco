package App::Netdisco::Daemon::Worker::Poller::Device;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::SNMP 'snmp_connect';
use App::Netdisco::Util::Device 'get_device';
use App::Netdisco::Core::Discover ':all';
use App::Netdisco::Daemon::Util ':all';

use NetAddr::IP::Lite ':lower';

use Role::Tiny;
use namespace::clean;

# queue a discover job for all devices known to Netdisco
sub discoverall {
  my ($self, $job) = @_;

  my $devices = schema('netdisco')->resultset('Device')->get_column('ip');
  my $jobqueue = schema('netdisco')->resultset('Admin');

  schema('netdisco')->txn_do(sub {
    # clean up user submitted jobs older than 1min,
    # assuming skew between schedulers' clocks is not greater than 1min
    $jobqueue->search({
        action => 'discover',
        status => 'queued',
        entered => { '<' => \"(now() - interval '1 minute')" },
    })->delete;

    # is scuppered by any user job submitted in last 1min (bad), or
    # any similar job from another scheduler (good)
    $jobqueue->populate([
      map {{
          device => $_,
          action => 'discover',
          status => 'queued',
      }} ($devices->all)
    ]);
  });

  return job_done("Queued discover job for all devices");
}

# queue a discover job for one device, and its *new* neighbors
sub discover {
  my ($self, $job) = @_;

  my $host = NetAddr::IP::Lite->new($job->device);
  my $device = get_device($host->addr);

  if ($device->in_storage
      and $device->vendor and $device->vendor eq 'netdisco') {
      return job_done("Skipped discover for pseudo-device $host");
  }

  my $snmp = snmp_connect($device);
  if (!defined $snmp) {
      return job_error("discover failed: could not SNMP connect to $host");
  }

  store_device($device, $snmp);
  store_interfaces($device, $snmp);
  store_wireless($device, $snmp);
  store_vlans($device, $snmp);
  store_power($device, $snmp);
  store_modules($device, $snmp);
  discover_new_neighbors($device, $snmp);

  return job_done("Ended discover for ". $host->addr);
}

1;
