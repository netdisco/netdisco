package App::Netdisco::Worker::Plugin::Vlan;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Port 'is_vlan_interface';

register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $pn, $data) = map {$job->$_} qw/device port extra/;
  return Status->error('Missing device (-d).') if !defined $device;
  return Status->error('Missing port (-p).') if !defined $pn;
  return Status->error('Missing vlan (-e).') if !defined $data;

  vars->{'port'} = get_port($device, $pn)
    or return Status->error("Unknown port name [$pn] on device $device");

  return Status->error("Cannot alter native vlan (portctl_native_vlan)")
    unless setting('portctl_native_vlan');

  return Status->error("Cannot alter port: restricted function (portctl_nameonly)")
    if setting('portctl_nameonly');

  return Status->error("Cannot alter routed interface vlan")
    if is_vlan_interface(vars->{'port'});

  return Status->done("Vlan is able to run.");
});

true;
