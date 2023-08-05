package App::Netdisco::Worker::Plugin::Snapshot;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;
use App::Netdisco::Util::Snapshot qw/gather_browserdata browserdata_to_cache/;

use File::Spec::Functions qw(catdir catfile);
use File::Slurper 'write_text';
use File::Path 'make_path';

register_worker({ phase => 'check' }, sub {
  return Status->error('Missing device (-d).')
    unless defined shift->device;
  return Status->done('Snapshot is able to run');
});

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  # might restore a cache if there's one on disk
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("snapshot failed: could not SNMP connect to $device");

  if (not ($device->in_storage
           and not $device->is_pseudo
           and not $snmp->offline)) {
      return Status->error('Can only snapshot a discovered device.');
  }

  # TODO add extra vendor support
  gather_browserdata( $device, $snmp );

  # optional save to disk
  if ($job->port) {
      my $target_dir = catdir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'logs', 'snapshots');
      make_path($target_dir);
      my $target_file = catfile($target_dir, $device->ip);

      debug "snapshot $device - saving snapshot to $target_file";
      # TODO browserata_to_cache
      # write_text($target_file, $frozen);
  }

  return Status->done(
    sprintf "Snapshot data captured from %s", $device->ip);
});

true;
