package App::Netdisco::Worker::Plugin::Power;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;
use App::Netdisco::Util::Port ':all';

register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $port) = map {$job->$_} qw/device port/;

  return Status->error('Power failed: unable to interpret device param')
    unless defined $device;

  return Status->error("Power skipped: $device not yet discovered")
    unless $device->in_storage;

  return Status->error('Missing port (-p).') unless defined $job->port;

  vars->{'port'} = get_port($device, $port)
    or return Status->error("Unknown port name [$port] on device $device");

  return Status->error('Missing status (-e).') unless defined $job->subaction;

  merge_portctl_roles_from_db($job->username);
  return Status->error("Permission denied to alter power status")
    unless port_acl_service(vars->{'port'}, $device, $job->username);

  return Status->error("No PoE service on port [$port] on device $device")
    unless vars->{'port'}->power;

  return Status->done('Power is able to run');
});

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $pn) = map {$job->$_} qw/device port/;

  # munge data
  (my $data = $job->subaction) =~ s/-\w+//; # remove -other
  $data = 'true'  if $data =~ m/^(on|yes|up)$/;
  $data = 'false' if $data =~ m/^(off|no|down)$/;

  # snmp connect using rw community
  my $snmp = App::Netdisco::Transport::SNMP->writer_for($device)
    or return Status->defer("failed to connect to $device to set power");

  my $powerid = get_powerid($snmp, vars->{'port'})
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
  vars->{'port'}->power->update({
    admin => $data,
    status => ($data eq 'false' ? 'disabled' : 'searching'),
  });

  return Status->done("Updated [$pn] power status on $device to [$data]");
});

true;
