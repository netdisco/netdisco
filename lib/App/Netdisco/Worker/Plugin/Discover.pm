package App::Netdisco::Worker::Plugin::Discover;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device 'is_discoverable_now';

register_worker({ stage => 'init' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  return Status->error('discover failed: unable to interpret device param')
    unless defined $device;

  my $host = $device->ip;

  return Status->error("discover failed: no device param (need -d ?)")
    if $host eq '0.0.0.0';

  return Status->defer("discover skipped: $host is pseudo-device")
    if $device->vendor and $device->vendor eq 'netdisco';

  return Status->defer("discover deferred: $host is not discoverable")
    unless is_discoverable_now($device);

  return Status->done('discover is able to run.');
});

true;
