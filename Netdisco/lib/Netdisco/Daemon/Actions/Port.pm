package Netdisco::Daemon::Actions::Port;

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

1;
