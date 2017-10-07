package App::Netdisco::Worker::Plugin::Power;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;
use App::Netdisco::Util::Port ':all';

register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;
  return Status->error('Missing device (-d).') unless defined $job->device;
  return Status->error('Missing port (-p).') unless defined $job->port;
  return Status->error('Missing status (-e).') unless defined $job->subaction;

  my $port = get_port($job->device, $job->port)
    or return Status->error(sprintf "Unknown port name [%s] on device %s",
                              $job->port, $job->device);

  my $vlan_reconfig_check = vlan_reconfig_check($port);
  return Status->error("Cannot alter vlan: $vlan_reconfig_check")
    if $vlan_reconfig_check;

  return Status->error("No PoE service on port [$pn] on device $device")
    unless $port->power;

  return Status->done('Power is able to run');
});

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $pn) = map {$job->$_} qw/device port/;
  my $port = get_port($device, $pn);

  # munge data
  (my $data = $job->subaction) =~ s/-\w+//; # remove -other
  $data = 'true'  if $data =~ m/^(on|yes|up)$/;
  $data = 'false' if $data =~ m/^(off|no|down)$/;

  # snmp connect using rw community
  my $snmp = App::Netdisco::Transport::SNMP->writer_for($device)
    or return Status->defer("failed to connect to $device to update vlan");

  my $powerid = get_powerid($snmp, $port)
    or return Status->error("failed to get power ID for [$pn] from $device");

  my $rv = $snmp->set_peth_port_admin($data, $powerid);

  if (!defined $rv) {
      return Status->error(sprintf 'failed to set [%s] power to [%s] on [%s]: %s',
                    $pn, $data, $device, ($snmp->error || ''));
  }

  # confirm the set happened
  $snmp->clear_cache;
  my $state = ($snmp->peth_port_admin($powerid) || '');
  if (ref {} ne ref $state or $state->{$powerid} ne $data) {
      return Status->error("Verify of [$pn] power failed on $device");
  }

  # update netdisco DB
  $port->power->update({
    admin => $data,
    status => ($data eq 'false' ? 'disabled' : 'searching'),
  });

  return Status->done("Updated [$pn] power status on $device to [$data]");
});

true;
