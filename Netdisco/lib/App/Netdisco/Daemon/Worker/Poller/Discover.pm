package App::Netdisco::Daemon::Worker::Poller::Discover;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::SNMP 'snmp_connect';
use App::Netdisco::Util::Device 'get_device';
use App::Netdisco::Util::DiscoverAndStore ':all';
use App::Netdisco::Daemon::Worker::Interactive::Util ':all';

use NetAddr::IP::Lite ':lower';

use Role::Tiny;
use namespace::clean;

# queue a discover job for all devices known to Netdisco
sub refresh {
  my ($self, $job) = @_;

  my $devices = schema('netdisco')->resultset('Device')->get_column('ip');

  schema('netdisco')->resultset('Admin')->populate([
    map {{
        device => $_,
        action => 'discover',
        status => 'queued',
    }} ($devices->all)
  ]);

  return job_done("Queued discover job for all devices");
}

sub discover {
  my ($self, $job) = @_;

  my $host = NetAddr::IP::Lite->new($job->device);
  my $device = get_device($host->addr);
  my $snmp = snmp_connect($device);

  if (!defined $snmp) {
      return job_error("Discover failed: could not SNMP connect to $host");
  }

  store_device($device, $snmp);
  store_interfaces($device, $snmp);
  #store_wireless($device, $snmp);
  #store_vlans($device, $snmp);
  #store_power($device, $snmp);
  #store_modules($device, $snmp);

  return job_done("Ended Discover for $host");
}

1;
