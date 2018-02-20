package App::Netdisco::Worker::Plugin::Discover::PortProperties;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use Dancer::Plugin::DBIC 'schema';

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  return unless $device->in_storage;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  my $interfaces = $snmp->interfaces;
  my $err_cause = $snmp->i_err_disable_cause;

  if (!defined $err_cause or !defined $interfaces) {
      return Status->info(sprintf ' [%s] props - 0 errored ports', $device->ip);
  }

  # build device port properties info suitable for DBIC
  my @portproperties;
  foreach my $entry (keys %$err_cause) {
      my $port = $interfaces->{$entry};
      next unless $port;

      push @portproperties, {
          port => $port,
          error_disable_cause => $err_cause->{$entry},
      };
  }

  schema('netdisco')->txn_do(sub {
    my $gone = $device->properties_ports->delete;
    debug sprintf ' [%s] props - removed %d ports with properties',
      $device->ip, $gone;
    $device->properties_ports->populate(\@portproperties);

    return Status->info(sprintf ' [%s] props - added %d new port properties',
      $device->ip, scalar @portproperties);
  });
});

true;
