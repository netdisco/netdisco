package App::Netdisco::Worker::Plugin::Discover::Snapshot;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Worker::Plugin;
use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::SNMP qw/sortable_oid get_oidmap get_munges/;
use aliased 'App::Netdisco::Worker::Status';

use Storable 'nfreeze';
use MIME::Base64 'encode_base64';

register_worker({ phase => 'late' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  return unless $device->in_storage
    and not $device->oids->count and $snmp->offline;

  my %oidmap = get_oidmap();
  my %munges = get_munges($snmp);
  my $cache  = $snmp->cache;
  my %seenoid = ();

  my $frozen = encode_base64( nfreeze( $cache ) );
  $device->update_or_create_related('snapshot', { cache => $frozen });

  my @oids = map {{
    oid => $_,
    oid_parts => [ grep {length} (split m/\./, $_) ],
    leaf  => $oidmap{$_},
    munge => $munges{ $oidmap{$_} },
    value => encode_base64( nfreeze( [(exists $cache->{'store'}{$_} ? $cache->{'store'}{$_} : $cache->{'_'. $_})] ) ),
  }} sort {sortable_oid($a) cmp sortable_oid($b)}
     grep {exists $oidmap{$_}}
     grep {not $seenoid{$_}++}
     grep {m/^\.1/}
     map {s/^_//; $_}
     keys %$cache;

  schema('netdisco')->txn_do(sub {
    my $gone = $device->oids->delete;
    debug sprintf 'snapshot %s - removed %d oids from db',
      $device->ip, $gone;
    $device->oids->populate(\@oids);
    debug sprintf 'snapshot %s - added %d new oids to db',
      $device->ip, scalar @oids;
  });

  return Status
    ->info(sprintf ' [%s] snapshot - oids and cache stored', $job->device);
});

true;
