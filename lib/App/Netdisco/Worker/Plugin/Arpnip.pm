package App::Netdisco::Worker::Plugin::Arpnip;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device 'is_arpnipable_now';

register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  return Status->error('arpnip failed: unable to interpret device param')
    unless defined $device;

  return Status->error("arpnip skipped: $device not yet discovered")
    unless $device->in_storage;

  return Status->defer("arpnip skipped: $device has no layer 3 capability")
    unless $device->has_layer(3);

  return Status->defer("arpnip deferred: $device is not arpnipable")
    unless is_arpnipable_now($device);

  return Status->done('arpnip is able to run');
});

true;
