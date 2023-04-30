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
  my ($device, $port) = map {$job->$_} qw/device port/;

  # support for Hooks
  vars->{'hook_data'} = { $device->get_columns };
  delete vars->{'hook_data'}->{'snmp_comm'}; # for privacy

  $port = ($port ? 1 : 0);
  my $happy = delete_device($device, $port);

  if ($happy) {
      return Status->done("Deleted device: $device")
  }
  else {
      return Status->error("Failed to delete device: $device")
  }
});

true;
