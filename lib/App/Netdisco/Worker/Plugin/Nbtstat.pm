package App::Netdisco::Worker::Plugin::Nbtstat;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device 'is_macsuckable';

register_worker({ stage => 'init' }, sub {
  my ($job, $workerconf) = @_;

  return Status->error('nbtstat failed: unable to interpret device param')
    unless defined $job->device;

  return Status->defer(sprintf 'nbtstat deferred: %s is not macsuckable', $job->device->ip)
    unless is_macsuckable($job->device);

  return Status->done('Nbtstat is able to run.');
});

true;
