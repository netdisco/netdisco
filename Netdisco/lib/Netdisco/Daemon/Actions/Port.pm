package Netdisco::Daemon::Actions::Port;

use Netdisco::Util::Connect ':all';
use Netdisco::Util::Permissions 'port_reconfig_check';
use Netdisco::Daemon::Actions::Util ':all';

use namespace::clean;
use Moo::Role;

sub portcontrol {
  my ($self, $job) = @_;

  my $ip = $job->device;
  my $pn = $job->port;
  (my $dir = $job->subaction) =~ s/-\w+//;

  my $port = get_port($ip, $pn)
    or return error("Unknown port name [$pn] on device [$ip]");

  my $reconfig_check = port_reconfig_check($port);
  return error("Cannot alter port: $reconfig_check")
    if length $reconfig_check;

  # snmp connect using rw community
  my $info = snmp_connect($ip)
    or return error("Failed to connect to device [$ip] to control port");

  my $iid = get_iid($port)
    or return error("Failed to get port ID for [$pn] from [$ip]");

  my $rv = $info->set_i_up_admin(lc($dir), $iid);

  return error("Failed to set [$pn] port status to [$dir] on [$ip]")
    if !defined $rv;

  # confirm the set happened
  $info->clear_cache;
  my $state = ($info->i_up_admin($iid) || '');
  if ($state ne $dir) {
      return error("Verify of [$pn] port status failed on [$ip]: $state");
  }

  # get device details from db
  my $device = $port->device
    or return error("Updated [$pn] port status on [$ip] but failed to update DB");

  # update netdisco DB
  $device->update({up_admin => $state});

  return done("Updated [$pn] port status on [$ip] to [$state]");
}

1;
