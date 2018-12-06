package App::Netdisco::Worker::Plugin::Vlan::Core;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;
use App::Netdisco::Util::Port ':all';

register_worker({ phase => 'early', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $pn) = map {$job->$_} qw/device port/;

  # snmp connect using rw community
  my $snmp = App::Netdisco::Transport::SNMP->writer_for($device)
    or return Status->defer("failed to connect to $device to update vlan/pvid");

  vars->{'iid'} = get_iid($snmp, vars->{'port'})
    or return Status->error("Failed to get port ID for [$pn] from $device");

  return Status->info("Vlan set can continue.");
});

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  return unless defined vars->{'iid'};
  _action($job, 'pvid');
  return _action($job, 'vlan');
});

sub _action {
  my ($job, $slot) = @_;
  my ($device, $pn, $data) = map {$job->$_} qw/device port extra/;

  my $getter = "i_${slot}";
  my $setter = "set_i_${slot}";

  # snmp connect using rw community
  my $snmp = App::Netdisco::Transport::SNMP->writer_for($device)
    or return Status->defer("failed to connect to $device to update $slot");

  my $rv = $snmp->$setter($data, vars->{'iid'});

  if (!defined $rv) {
      return Status->error(sprintf 'Failed to set [%s] %s to [%s] on $device: %s',
                    $pn, $slot, $data, ($snmp->error || ''));
  }

  # confirm the set happened
  $snmp->clear_cache;
  my $state = ($snmp->$getter(vars->{'iid'}) || '');
  if (ref {} ne ref $state or $state->{ vars->{'iid'} } ne $data) {
      return Status->error("Verify of [$pn] $slot failed on $device");
  }

  # update netdisco DB
  vars->{'port'}->update({$slot => $data});

  return Status->done("Updated [$pn] $slot on [$device] to [$data]");
}

true;
