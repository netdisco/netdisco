package Netdisco::PortControl;

use strict;
use warnings FATAL => 'all';

use Netdisco::Util ':port_control';
use Try::Tiny;

sub set_location {
  my ($self, $job) = @_;

  try {
      # snmp connect using rw community
      my $info = snmp_connect($job->device)
        or return ();

      my $location = ($job->subaction || '');
      my $rv = $info->set_location($location);

      if (!defined $rv) {
          my $log = sprintf 'Failed to set location on [%s]: %s',
            $job->device, ($info->error || '');
          return ('error', $log);
      }

      # double check
      $info->clear_cache;
      my $new_location = ($info->location || '');
      if ($new_location ne $location) {
          my $log = sprintf 'Failed to update location on [%s] to [%s]',
            $job->device, ($location);
          return ('error', $log);
      }

      # get device details from db
      my $device = get_device($job->device)
        or return ();

      # update netdisco DB
      $device->update({location => $location});

      my $log = sprintf 'Updated location on [%s] to [%s]',
        $job->device, $location;
      return ('done', $log);
  }
  catch {
      return( 'error',
        (sprintf 'Failed to update location on [%s]: %s', $job->device, $_)
      );
  };
}

1;
