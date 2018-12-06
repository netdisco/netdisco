package App::Netdisco::Worker::Plugin::Macsuck;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device 'is_macsuckable_now';

register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  return Status->error('macsuck failed: unable to interpret device param')
    unless defined $device;

  return Status->error("macsuck skipped: $device not yet discovered")
    unless $device->in_storage;

  return Status->defer("macsuck skipped: $device is pseudo-device")
    if $device->is_pseudo;

  return Status->defer("macsuck skipped: $device has no layer 2 capability")
    unless $device->has_layer(2);

  return Status->defer("macsuck deferred: $device is not macsuckable")
    unless is_macsuckable_now($device);

  return Status->done('Macsuck is able to run.');
});

true;
