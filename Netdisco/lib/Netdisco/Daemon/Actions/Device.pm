package Netdisco::Daemon::Actions::Device;

use Netdisco::Util ':port_control';
use Try::Tiny;

sub set_location {
  my ($self, $job) = @_;
  return $self->_set_device_generic($job->device, 'location', $job->subaction);
}

sub set_contact {
  my ($self, $job) = @_;
  return $self->_set_device_generic($job->device, 'contact', $job->subaction);
}

sub _set_device_generic {
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

1;
