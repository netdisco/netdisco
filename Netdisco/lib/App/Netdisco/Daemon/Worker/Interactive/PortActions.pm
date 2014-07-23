package App::Netdisco::Daemon::Worker::Interactive::PortActions;

use App::Netdisco::Util::Port ':all';
use App::Netdisco::Util::SNMP 'snmp_connect_rw';
use App::Netdisco::Daemon::Util ':all';

use Role::Tiny;
use namespace::clean;

sub set_portname {
  my ($self, $job) = @_;
  return _set_port_generic($job, 'alias', 'name');
}

sub set_portcontrol {
  my ($self, $job) = @_;

  my $port = get_port($job->device, $job->port)
    or return job_error(sprintf "Unknown port name [%s] on device [%s]",
      $job->port, $job->device);

  my $reconfig_check = port_reconfig_check($port);
  return job_error("Cannot alter port: $reconfig_check")
    if $reconfig_check;

  # need to remove "-other" which appears for power/portcontrol
  (my $sa = $job->subaction) =~ s/-\w+//;
  $job->subaction($sa);

  return _set_port_generic($job, 'up_admin');
}

sub set_vlan {
  my ($self, $job) = @_;

  my $port = get_port($job->device, $job->port)
    or return job_error(sprintf "Unknown port name [%s] on device [%s]",
      $job->port, $job->device);

  my $port_reconfig_check = port_reconfig_check($port);
  return job_error("Cannot alter port: $port_reconfig_check")
    if $port_reconfig_check;

  my $vlan_reconfig_check = vlan_reconfig_check($port);
  return job_error("Cannot alter vlan: $vlan_reconfig_check")
    if $vlan_reconfig_check;

  return _set_port_generic($job, 'untagged', 'vlan');
}

sub _set_port_generic {
  my ($job, $slot, $column) = @_;
  $column ||= $slot;

  my $ip = $job->device;
  my $pn = $job->port;
  my $data = $job->subaction;

  my $port = get_port($ip, $pn)
    or return job_error("Unknown port name [$pn] on device [$ip]");

  # snmp connect using rw community
  my $info = snmp_connect_rw($ip)
    or return job_error("Failed to connect to device [$ip] to control port");

  my $iid = get_iid($info, $port)
    or return job_error("Failed to get port ID for [$pn] from [$ip]");

  my $method = 'set_i_'. $slot;
  my $rv = $info->$method($data, $iid);

  if (!defined $rv) {
      return job_error(sprintf 'Failed to set [%s] %s to [%s] on [%s]: %s',
                    $pn, $slot, $data, $ip, ($info->error || ''));
  }

  # confirm the set happened
  $info->clear_cache;
  my $check_method = 'i_'. $slot;
  my $state = ($info->$check_method($iid) || '');
  if (ref {} ne ref $state or $state->{$iid} ne $data) {
      return job_error("Verify of [$pn] $slot failed on [$ip]");
  }

  # update netdisco DB
  $port->update({$column => $data});

  return job_done("Updated [$pn] $slot status on [$ip] to [$data]");
}

sub set_power {
  my ($self, $job) = @_;

  my $port = get_port($job->device, $job->port)
    or return job_error(sprintf "Unknown port name [%s] on device [%s]",
      $job->port, $job->device);

  return job_error("No PoE service on port [%s] on device [%s]")
    unless $port->power;

  my $reconfig_check = port_reconfig_check($port);
  return job_error("Cannot alter port: $reconfig_check")
    if $reconfig_check;


  my $ip = $job->device;
  my $pn = $job->port;
  (my $data = $job->subaction) =~ s/-\w+//; # remove -other

  # snmp connect using rw community
  my $info = snmp_connect_rw($ip)
    or return job_error("Failed to connect to device [$ip] to control port");

  my $powerid = get_powerid($info, $port)
    or return job_error("Failed to get power ID for [$pn] from [$ip]");

  my $rv = $info->set_peth_port_admin($data, $powerid);

  if (!defined $rv) {
      return job_error(sprintf 'Failed to set [%s] power to [%s] on [%s]: %s',
                    $pn, $data, $ip, ($info->error || ''));
  }

  # confirm the set happened
  $info->clear_cache;
  my $state = ($info->peth_port_admin($powerid) || '');
  if (ref {} ne ref $state or $state->{$powerid} ne $data) {
      return job_error("Verify of [$pn] power failed on [$ip]");
  }

  # update netdisco DB
  $port->power->update({
    admin => $data,
    status => ($data eq 'false' ? 'disabled' : 'searching'),
  });

  return job_done("Updated [$pn] power status on [$ip] to [$data]");
}

1;
