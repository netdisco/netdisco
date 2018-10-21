package App::Netdisco::Worker::Plugin::Delete;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device 'delete_device';

register_worker({ phase => 'check' }, sub {
  return Status->error('Missing device (-d).')
    unless shift->device;
  return Status->done('Delete is able to run');
});

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $port, $extra) = map {$job->$_} qw/device port extra/;

  $port = ($port ? 1 : 0);
  delete_device($device, $port, $extra);
  return Status->done("Deleted device: $device");
});

true;
