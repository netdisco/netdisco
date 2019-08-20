package App::Netdisco::Worker::Plugin::PortControl;

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

  vars->{'port'} = get_port($job->device, $job->port)
    or return Status->error(sprintf "Unknown port name [%s] on device %s",
                              $job->port, $job->device);

  my $port_reconfig_check = port_reconfig_check(vars->{'port'});
  return Status->error("Cannot alter port: $port_reconfig_check")
    if $port_reconfig_check;

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
