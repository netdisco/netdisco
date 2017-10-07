package App::Netdisco::Worker::Plugin::Vlan;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Port ':all';

register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $pn, $data) = map {$job->$_} qw/device port extra/;
  return Status->error('Missing device (-d).') if !defined $device;
  return Status->error('Missing port (-p).') if !defined $pn;
  return Status->error('Missing vlan (-e).') if !defined $data;

  vars->{'port'} = get_port($device, $pn)
    or return Status->error("Unknown port name [$pn] on device $device");

  my $port_reconfig_check = port_reconfig_check(vars->{'port'});
  return Status->error("Cannot alter port: $port_reconfig_check")
    if $port_reconfig_check;

  my $vlan_reconfig_check = vlan_reconfig_check(vars->{'port'});
  return Status->error("Cannot alter vlan: $vlan_reconfig_check")
    if $vlan_reconfig_check;

  return Status->done("Vlan is able to run.");
});

true;
