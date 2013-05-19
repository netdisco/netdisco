package App::Netdisco::Daemon::Worker::Poller::Arpnip;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::SNMP 'snmp_connect';
use App::Netdisco::Util::Device 'get_device';
use App::Netdisco::Util::Arpnip ':all';
use App::Netdisco::Daemon::Util ':all';

use NetAddr::IP::Lite ':lower';

use Role::Tiny;
use namespace::clean;

sub arpnip {
  my ($self, $job) = @_;

  my $host = NetAddr::IP::Lite->new($job->device);
  my $device = get_device($host->addr);

  if ($device->in_storage
      and $device->vendor and $device->vendor eq 'netdisco') {
      return job_done("Skipped arpnip for pseudo-device $host");
  }

  my $snmp = snmp_connect($device);
  if (!defined $snmp) {
      return job_error("arpnip failed: could not SNMP connect to $host");
  }

  unless ($snmp->has_layer(3)) {
      return job_done("Skipped arpnip for device $host without OSI layer 3 capability");
  }

  do_arpnip($device, $snmp);

  return job_done("Ended arpnip for $host");
}

1;
