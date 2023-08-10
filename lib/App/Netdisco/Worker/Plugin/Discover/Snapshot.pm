package App::Netdisco::Worker::Plugin::Discover::Snapshot;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Worker::Plugin;
use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Snapshot 'dump_cache_to_browserdata';

use Storable 'nfreeze';
use MIME::Base64 'encode_base64';

use aliased 'App::Netdisco::Worker::Status';

register_worker({ phase => 'late' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  return unless $device->in_storage
    and not $device->oids->count and $snmp->offline;

  dump_cache_to_browserdata( $device, $snmp );

  my $frozen = encode_base64( nfreeze( $snmp->cache ) );
  $device->update_or_create_related('snapshot', { cache => $frozen });

  return Status
    ->info(sprintf ' [%s] discover - oids and cache stored', $device);
});

true;
