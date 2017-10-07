package App::Netdisco::Worker::Plugin::Vlan::Port;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;
use App::Netdisco::Util::Port ':all';

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $pn, $data) = map {$job->$_} qw/device port extra/;

  # snmp connect using rw community
  my $snmp = App::Netdisco::Transport::SNMP->writer_for($device)
    or return Status->defer("failed to connect to $device to update pvid");

  my $port = get_port($device, $pn)
    or return Status->error("Unknown port name [$pn] on device $device");

  my $iid = get_iid($snmp, $port)
    or return Status->error("Failed to get port ID for [$pn] from $device");

  my $rv = $snmp->set_i_pvid($data, $iid);

  if (!defined $rv) {
      return Status->error(sprintf 'Failed to set [%s] pvid to [%s] on $device: %s',
                    $pn, $data, ($snmp->error || ''));
  }

  # confirm the set happened
  $snmp->clear_cache;
  my $state = ($snmp->i_pvid($iid) || '');
  if (ref {} ne ref $state or $state->{$iid} ne $data) {
      return Status->error("Verify of [$pn] pvid failed on $device");
  }

  # update netdisco DB
  $port->update({pvid => $data});

  return Status->done("Updated [$pn] pvid on [$device] to [$data]");
});

true;
