package App::Netdisco::Worker::Plugin::Nbtstat;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Node 'is_nbtstatable';

register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;

  return Status->error('nbtstat failed: unable to interpret device param')
    unless defined $job->device;

  return Status->info(sprintf 'nbtstat skipped: %s is not nbtstable', $job->device->ip)
    unless is_nbtstatable($job->device->ip);

  return Status->done('Nbtstat is able to run.');
});

true;

