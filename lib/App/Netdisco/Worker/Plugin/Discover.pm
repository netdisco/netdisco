package App::Netdisco::Worker::Plugin::Discover;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device 'is_discoverable_now';

register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  return Status->error('discover failed: unable to interpret device param')
    unless defined $device;

  return Status->error("discover failed: no device param (need -d ?)")
    if $device->ip eq '0.0.0.0';

  return Status->defer("discover skipped: $device is pseudo-device")
    if $device->is_pseudo;

  # runner has already called get_device to promote $job->device
  return $job->cancel("fresh discover cancelled: $device already known")
    if $device->in_storage
       and ($job->subaction eq 'with-nodes' and not $job->username);

  return Status->defer("discover deferred: $device is not discoverable")
    unless is_discoverable_now($device);

  return Status->done('Discover is able to run.');
});

true;
