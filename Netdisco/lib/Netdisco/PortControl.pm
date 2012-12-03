package Netdisco::PortControl;

use Netdisco::Util ':port_control';
use Try::Tiny;

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
        or return ();

      my $method = 'set_'. $slot;
      my $rv = $info->$method($data);

      if (!defined $rv) {
          my $log = sprintf 'Failed to set %s on [%s]: %s',
            $slot, $ip, ($info->error || '');
          return ('error', $log);
      }

      # double check
      $info->clear_cache;
      my $new_data = ($info->$slot || '');
      if ($new_data ne $data) {
          my $log = sprintf 'Failed to update %s on [%s] to [%s]',
            $slot, $ip, $data;
          return ('error', $log);
      }

      # get device details from db
      my $device = get_device($ip)
        or return ();

      # update netdisco DB
      $device->update({$slot => $data});

      my $log = sprintf 'Updated %s on [%s] to [%s]',
        $slot, $ip, $data;
      return ('done', $log);
  }
  catch {
      return( 'error',
        (sprintf 'Failed to update %s on [%s]: %s', $slot, $ip, $_)
      );
  };
}

1;
