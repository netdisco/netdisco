package App::Netdisco::Daemon::Worker::Poller::Macsuck;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::SNMP 'snmp_connect';
use App::Netdisco::Util::Device 'get_device';
use App::Netdisco::Core::Macsuck ':all';
use App::Netdisco::Daemon::Util ':all';

use NetAddr::IP::Lite ':lower';

use Role::Tiny;
use namespace::clean;

# queue a macsuck job for all devices known to Netdisco
sub macwalk {
  my ($self, $job) = @_;

  my $devices = schema('netdisco')->resultset('Device')->get_column('ip');
  my $jobqueue = schema('netdisco')->resultset('Admin');

  schema('netdisco')->txn_do(sub {
    # clean up user submitted jobs older than 1min,
    # assuming skew between schedulers' clocks is not greater than 1min
    $jobqueue->search({
        action => 'macsuck',
        status => 'queued',
        entered => { '<' => \"(now() - interval '1 minute')" },
    })->delete;

    # is scuppered by any user job submitted in last 1min (bad), or
    # any similar job from another scheduler (good)
    $jobqueue->populate([
      map {{
          device => $_,
          action => 'macsuck',
          status => 'queued',
      }} ($devices->all)
    ]);
  });

  return job_done("Queued macsuck job for all devices");
}

sub macsuck {
  my ($self, $job) = @_;

  my $host = NetAddr::IP::Lite->new($job->device);
  my $device = get_device($host->addr);

  if ($device->in_storage
      and $device->vendor and $device->vendor eq 'netdisco') {
      return job_done("Skipped macsuck for pseudo-device $host");
  }

  my $snmp = snmp_connect($device);
  if (!defined $snmp) {
      return job_error("macsuck failed: could not SNMP connect to $host");
  }

  unless ($snmp->has_layer(2)) {
      return job_done("Skipped macsuck for device $host without OSI layer 2 capability");
  }

  do_macsuck($device, $snmp);

  return job_done("Ended macsuck for ". $host->addr);
}

1;
