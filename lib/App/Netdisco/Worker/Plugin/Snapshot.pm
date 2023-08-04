package App::Netdisco::Worker::Plugin::Snapshot;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;
use App::Netdisco::Util::SNMP qw/sortable_oid get_munges/;
use Dancer::Plugin::DBIC 'schema';

use File::Spec::Functions qw(catdir catfile);
use MIME::Base64 'encode_base64';
use File::Slurper 'write_text';
use File::Path 'make_path';
use Storable 'nfreeze';

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

  # get MIBs loaded for device
  my @mibs = keys %{ $snmp->mibs() };
  debug sprintf "snapshot: loaded %d MIBs", scalar @mibs;

  # get qualified leafs for those MIBs from snmp_object
  my %oidmap = map { ((join '::', $_->{mib}, $_->{leaf}) => $_->{oid}) }
               schema('netdisco')->resultset('SNMPObject')
                                 ->search({
                                     mib => { -in => \@mibs },
                                     num_children => 0,
                                     leaf => { '!~' => 'anonymous#\d+$' },
                                     -or => [
                                       type   => { '<>' => '' },
                                       access => { '~' => '^(read|write)' },
                                       \'oid_parts[array_length(oid_parts,1)] = 0'
                                     ],
                                   },{columns => [qw/mib oid leaf/], order_by => 'oid_parts'})
                                 ->hri->all;

  # gather each of the leafs
  debug sprintf "snapshot: gathering %d MIB Objects", scalar keys %oidmap;
  foreach my $qleaf (keys %oidmap) {
      my $snmpqleaf = $qleaf;
      $snmpqleaf =~ s/[-:]/_/g;
      $snmp->$snmpqleaf;
  }

  my %munges = get_munges($snmp);
  my $cache  = $snmp->cache;

  # optional save to disk
  if ($job->port) {
      my $target_dir = catdir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'logs', 'snapshots');
      make_path($target_dir);
      my $target_file = catfile($target_dir, $device->ip);

      debug "snapshot $device - saving snapshot to $target_file";
      my $frozen = encode_base64( nfreeze( $cache ) );
      write_text($target_file, $frozen);
  }

  # the cache has the qualified names like _SNMPv2_MIB__sysDescr
  # so need to convert to something suitable for the device_browser table

  my @oids = ();
  foreach my $qleaf (sort {sortable_oid($oidmap{$a}) cmp sortable_oid($oidmap{$b})} keys %oidmap) {
      my $leaf = $qleaf;
      $leaf =~ s/.+:://;

      my $snmpqleaf = $qleaf;
      $snmpqleaf =~ s/[-:]/_/g;

      push @oids, {
        oid => $oidmap{$qleaf},
        oid_parts => [ grep {length} (split m/\./, $oidmap{$qleaf}) ],
        leaf  => $leaf,
        munge => ($munges{$snmpqleaf} || $munges{$leaf}),
        value => encode_base64( nfreeze( [(exists $cache->{'store'}{$snmpqleaf} ? $cache->{'store'}{$snmpqleaf}
                                                                                : $cache->{'_'. $snmpqleaf})] ) ),
      };
  }

  schema('netdisco')->txn_do(sub {
    my $gone = $device->oids->delete;
    debug sprintf 'snapshot %s - removed %d oids from db',
      $device->ip, $gone;
    $device->oids->populate(\@oids);
    debug sprintf 'snapshot %s - added %d new oids to db',
      $device->ip, scalar @oids;
  });

  return Status->done(
    sprintf "Snapshot data captured from %s", $device->ip);
});

true;
