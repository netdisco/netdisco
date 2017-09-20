package App::Netdisco::Worker::Plugin::PortName;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;
use App::Netdisco::Util::Port ':all';

register_worker({ stage => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $pn, $data) = map {$job->$_} qw/device port extra/;
  return Status->error('Missing device (-d).') if !defined $device;
  return Status->error('Missing port (-p).') if !defined $pn;
  return Status->error('Missing name (-e).') if !defined $data;

  # snmp connect using rw community
  my $snmp = App::Netdisco::Transport::SNMP->writer_for($device)
    or return Status->defer("failed to connect to $device to update alias");

  my $port = get_port($device, $pn)
    or return Status->error("Unknown port name [$pn] on device $device");

  my $iid = get_iid($snmp, $port)
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

  # update netdisco DB
  $port->update({name => $data});

  return Status->done("Updated [$pn] alias on [$device] to [$data]");
});

true;
