package App::Netdisco::Worker::Plugin::Vlan;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Port qw/get_port port_acl_pvid/;

register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $port, $data) = map {$job->$_} qw/device port extra/;

  return Status->error('Vlan failed: unable to interpret device param')
    unless defined $device;

  return Status->error("Vlan skipped: $device not yet discovered")
    unless $device->in_storage;

  return Status->error('Missing port (-p).') unless defined $job->port;

  vars->{'port'} = get_port($device, $port)
    or return Status->error("Unknown port name [$port] on device $device");

  return Status->error('Missing vlan (-e).') unless defined $job->subaction;

  merge_portctl_roles_from_db($job->username);
  return Status->error("Permission denied to alter native vlan")
    unless port_acl_pvid(vars->{'port'}, $device, $job->username);

  return Status->done("Vlan is able to run.");
});

true;
