package App::Netdisco::Worker::Plugin::Vlan;

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
  return Status->error('Missing vlan (-e).') if !defined $data;

  my $port = get_port($device, $pn)
    or return Status->error("Unknown port name [$pn] on device $device");

  my $port_reconfig_check = port_reconfig_check($port);
  return Status->error("Cannot alter port: $port_reconfig_check")
    if $port_reconfig_check;

  my $vlan_reconfig_check = vlan_reconfig_check($port);
  return Status->error("Cannot alter vlan: $vlan_reconfig_check")
    if $vlan_reconfig_check;

  return Status->done("Check phase for update [$pn] vlan $data done.");
});

register_worker({ stage => 'main' }, sub {
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

register_worker({ stage => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $pn, $data) = map {$job->$_} qw/device port extra/;

  # snmp connect using rw community
  my $snmp = App::Netdisco::Transport::SNMP->writer_for($device)
    or return Status->defer("failed to connect to $device to update vlan");

  my $port = get_port($device, $pn)
    or return Status->error("Unknown port name [$pn] on device $device");

  my $iid = get_iid($snmp, $port)
    or return Status->error("Failed to get port ID for [$pn] from $device");

  my $rv = $snmp->set_i_vlan($data, $iid);

  if (!defined $rv) {
      return Status->error(sprintf 'Failed to set [%s] vlan to [%s] on $device: %s',
                    $pn, $data, ($snmp->error || ''));
  }

  # confirm the set happened
  $snmp->clear_cache;
  my $state = ($snmp->i_vlan($iid) || '');
  if (ref {} ne ref $state or $state->{$iid} ne $data) {
      return Status->error("Verify of [$pn] vlan failed on $device");
  }

  # update netdisco DB
  $port->update({vlan => $data});

  return Status->done("Updated [$pn] vlan on [$device] to [$data]");
});

true;
