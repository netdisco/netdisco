package App::Netdisco::Worker::Plugin::Snapshot;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;
use App::Netdisco::Util::Snapshot qw/
  gather_every_mib_object
  dump_cache_to_browserdata
  add_snmpinfo_aliases
/;

use MIME::Base64 qw/encode_base64/;
use Storable qw/nfreeze/;
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

  if (not ($device->in_storage
           and not $device->is_pseudo)) {
      return Status->error('Can only snapshot a real discovered device.');
  }

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("snapshot failed: could not SNMP connect to $device");

  if ($snmp->offline) {
      return Status->error('Can only snapshot a real device.');
  }

  gather_every_mib_object( $device, $snmp, split m/,/, ($job->extra || '') );
  add_snmpinfo_aliases($snmp);
  dump_cache_to_browserdata( $device, $snmp );

  if ($job->port) {
      my $frozen = encode_base64( nfreeze( $snmp->cache ) );

      if ($job->port =~ m/^(?:both|db)$/) {
          debug "snapshot $device - saving snapshot to database";
          $device->update_or_create_related('snapshot', { cache => $frozen });
      }

      if ($job->port =~ m/^(?:both|file)$/) {
          my $target_dir = catdir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'logs', 'snapshots');
          make_path($target_dir);
          my $target_file = catfile($target_dir, $device->ip);

          debug "snapshot $device - saving snapshot to $target_file";
          write_text($target_file, $frozen);
      }
  }

  return Status->done(
    sprintf "Snapshot data captured from %s", $device->ip);
});

true;
