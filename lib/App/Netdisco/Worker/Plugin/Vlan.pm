package App::Netdisco::Worker::Plugin::Vlan;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Port qw/get_port port_acl_pvid/;

register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $port, $data) = map {$job->$_} qw/device port extra/;

  return Status->error('Missing device (-d).') if !defined $device;
  return Status->error('Missing port (-p).') if !defined $port;
  return Status->error('Missing vlan (-e).') if !defined $data;

  ($device, vars->{'port'}) = get_port($device, $port)
    or return Status->error("Unknown port name [$port] on device $device");

  return Status->error("Permission denied to alter native vlan")
    unless port_acl_pvid(vars->{'port'}, $device, $job->username);

  return Status->done("Vlan is able to run.");
});

true;
