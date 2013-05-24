package App::Netdisco::Daemon::Worker::Poller::Macsuck;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::SNMP 'snmp_connect';
use App::Netdisco::Util::Device 'get_device';
use App::Netdisco::Util::Macsuck ':all';
use App::Netdisco::Daemon::Util ':all';

use NetAddr::IP::Lite ':lower';

use Role::Tiny;
use namespace::clean;

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
