package Netdisco::PortControl::Actions;

use Netdisco::Util ':port_control';
use Try::Tiny;

sub portcontrol {
  my ($self, $job) = @_;

  my $ip = $job->device;
  my $pn = $job->port;
  (my $dir = $job->subaction) =~ s/-\w+//;

  try {
      my $port = get_port($ip, $pn)
        or return _error("Unknown port name [$pn] on device [$ip]");

      my $reconfig_check = port_reconfig_check($port);
      return _error("Cannot alter port: $reconfig_check")
        if length $reconfig_check;

      # snmp connect using rw community
      my $info = snmp_connect($ip)
        or return _error("Failed to connect to device [$ip] to control port");

      my $iid = get_iid($port)
        or return _error("Failed to get port ID for [$pn] from [$ip]");

      my $rv = $info->set_i_up_admin(lc($dir), $iid);

      return _error("Failed to set [$pn] port status to [$dir] on [$ip]")
        if !defined $rv;

      # confirm the set happened
      $info->clear_cache;
      my $state = ($info->i_up_admin($iid) || '');
      if ($state ne $dir) {
          return _error("Verify of [$pn] port status failed on [$ip]: $state");
      }

      # get device details from db
      my $device = $port->device
        or return _error("Updated [$pn] port status on [$ip] but failed to update DB");

      # update netdisco DB
      $device->update({up_admin => $state});

      return _done("Updated [$pn] port status on [$ip] to [$state]");
  }
  catch {
      return _error("Failed to update [$pn] port status on [$ip]: $_");
  };
}


sub set_location {
  my ($self, $job) = @_;
  return $self->_set_generic($job->device, 'location', $job->subaction);
}

sub set_contact {
  my ($self, $job) = @_;
  return $self->_set_generic($job->device, 'contact', $job->subaction);
}

sub _set_generic {
  my ($self, $ip, $slot, $data) = @_;
  $data ||= '';

  try {
      # snmp connect using rw community
      my $info = snmp_connect($ip)
        or return _error("Failed to connect to device [$ip] to update $slot");

      my $method = 'set_'. $slot;
      my $rv = $info->$method($data);

      if (!defined $rv) {
          return _error(sprintf 'Failed to set %s on [%s]: %s',
                        $slot, $ip, ($info->error || ''));
      }

      # confirm the set happened
      $info->clear_cache;
      my $new_data = ($info->$slot || '');
      if ($new_data ne $data) {
          return _error("Verify of $slot update failed on [$ip]: $new_data");
      }

      # get device details from db
      my $device = get_device($ip)
        or return _error("Updated $slot on [$ip] to [$data] but failed to update DB");

      # update netdisco DB
      $device->update({$slot => $data});

      return _done("Updated $slot on [$ip] to [$data]");
  }
  catch {
      return _error("Failed to update $slot on [$ip]: $_");
  };
}

sub _done  { return ('done',  shift) }
sub _error { return ('error', shift) }

1;
