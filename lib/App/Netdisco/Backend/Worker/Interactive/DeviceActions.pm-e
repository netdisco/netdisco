package App::Netdisco::Daemon::Worker::Interactive::DeviceActions;

use App::Netdisco::Util::SNMP 'snmp_connect_rw';
use App::Netdisco::Util::Device 'get_device';
use App::Netdisco::Daemon::Util ':all';

use Role::Tiny;
use namespace::clean;

sub location {
  my ($self, $job) = @_;
  return _set_device_generic($job->device, 'location', $job->subaction);
}

sub contact {
  my ($self, $job) = @_;
  return _set_device_generic($job->device, 'contact', $job->subaction);
}

sub _set_device_generic {
  my ($ip, $slot, $data) = @_;
  $data ||= '';

  # snmp connect using rw community
  my $info = snmp_connect_rw($ip)
    or return job_error("Failed to connect to device [$ip] to update $slot");

  my $method = 'set_'. $slot;
  my $rv = $info->$method($data);

  if (!defined $rv) {
      return job_error(sprintf 'Failed to set %s on [%s]: %s',
                    $slot, $ip, ($info->error || ''));
  }

  # confirm the set happened
  $info->clear_cache;
  my $new_data = ($info->$slot || '');
  if ($new_data ne $data) {
      return job_error("Verify of $slot update failed on [$ip]: $new_data");
  }

  # update netdisco DB
  my $device = get_device($ip);
  $device->update({$slot => $data});

  return job_done("Updated $slot on [$ip] to [$data]");
}

1;
