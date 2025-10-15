package App::Netdisco::Worker::Plugin::PortControl;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;
use App::Netdisco::Util::Port ':all';

register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $port, $data) = map {$job->$_} qw/device port extra/;

  return Status->error('PortControl failed: unable to interpret device param')
    unless defined $device;

  return Status->error("PortControl skipped: $device not yet discovered")
    unless $device->in_storage;

  return Status->error('Missing port (-p).') unless defined $job->port;

  vars->{'port'} = get_port($device, $port)
    or return Status->error("Unknown port name [$port] on device $device");

  return Status->error('Missing status (-e).') unless defined $job->subaction;

  merge_portctl_roles_from_db($job->username);
  return Status->error("Permission denied to change port status")
    unless port_acl_service(vars->{'port'}, $device, $job->username);

  return Status->done('PortControl is able to run');
});

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $pn) = map {$job->$_} qw/device port/;

  # need to remove "-other" which appears for power/portcontrol
  (my $sa = $job->subaction) =~ s/-\w+//;
  $job->subaction($sa);

  if ($sa eq 'bounce') {
    $job->subaction('down');
    my $status = _action($job);
    return $status if $status->not_ok;
    $job->subaction('up');
  }

  return _action($job);
});

sub _action {
  my $job = shift;
  my ($device, $pn, $data) = map {$job->$_} qw/device port subaction/;

  # snmp connect using rw community
  my $snmp = App::Netdisco::Transport::SNMP->writer_for($device)
    or return Status->defer("failed to connect to $device to update up_admin");

  my $iid = get_iid($snmp, vars->{'port'})
    or return Status->error("Failed to get port ID for [$pn] from $device");

  my $rv = $snmp->set_i_up_admin($data, $iid);

  if (!defined $rv) {
      return Status->error(sprintf "Failed to set [%s] up_admin to [%s] on $device: %s",
                    $pn, $data, ($snmp->error || ''));
  }

  # confirm the set happened
  $snmp->clear_cache;
  my $state = ($snmp->i_up_admin($iid) || '');
  if (ref {} ne ref $state or $state->{$iid} ne $data) {
      return Status->error("Verify of [$pn] up_admin failed on $device");
  }

  # update netdisco DB
  vars->{'port'}->update({up_admin => $data});

  return Status->done("Updated [$pn] up_admin on [$device] to [$data]");
}

true;
