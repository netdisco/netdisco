package App::Netdisco::Worker::Plugin::PortName;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;
use App::Netdisco::Util::Port ':all';

register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;
  return Status->error('Missing device (-d).') unless defined $job->device;
  return Status->error('Missing port (-p).') unless defined $job->port;
  return Status->error('Missing name (-e).') unless defined $job->subaction;

  vars->{'port'} = get_port($job->device, $job->port)
    or return Status->error(sprintf "Unknown port name [%s] on device %s",
                              $job->port, $job->device);

  return Status->done('PortName is able to run');
});

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $pn, $data) = map {$job->$_} qw/device port extra/;

  # update pseudo devices directly in database
  unless ($device->is_pseudo()) {
    # snmp connect using rw community
    my $snmp = App::Netdisco::Transport::SNMP->writer_for($device)
      or return Status->defer("failed to connect to $device to update alias");

    my $iid = get_iid($snmp, vars->{'port'})
      or return Status->error("Failed to get port ID for [$pn] from $device");

    my $rv = $snmp->set_i_alias($data, $iid);

    if (!defined $rv) {
        return Status->error(sprintf 'Failed to set [%s] alias to [%s] on $device: %s',
                      $pn, $data, ($snmp->error || ''));
    }

    # confirm the set happened
    $snmp->clear_cache;
    my $state = ($snmp->i_alias($iid) || '');
    if (ref {} ne ref $state or $state->{$iid} ne $data) {
        return Status->error("Verify of [$pn] alias failed on $device");
    }
  }

  # update netdisco DB
  vars->{'port'}->update({name => $data});

  return Status->done("Updated [$pn] alias on [$device] to [$data]");
});

true;
