package App::Netdisco::Worker::Plugin::Delete;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device 'delete_device';

register_worker({ stage => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $port, $extra) = map {$job->$_} qw/device port extra/;
  return Status->error('Missing device (-d).') if !defined $device;

  $port = ($port ? 1 : 0);
  delete_device($device, $port, $extra);
  return Status->done("Deleted device: $device");
});

true;
