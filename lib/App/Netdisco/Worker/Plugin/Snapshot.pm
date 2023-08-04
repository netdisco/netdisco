package App::Netdisco::Worker::Plugin::Snapshot;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;
use App::Netdisco::Util::SNMP qw/sortable_oid get_oidmap get_munges update_cache_from_instance/;
use Dancer::Plugin::DBIC 'schema';

use File::Spec::Functions qw(splitdir catdir catfile);
use MIME::Base64 'encode_base64';
use File::Slurper qw(read_lines write_text);
use File::Path 'make_path';
use Sub::Util 'subname';
use Storable qw(dclone nfreeze);
# use DDP;

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

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub walk_and_store {
  my ($device, $snmp, %oidmap) = @_;

  my $walk = {
    %{ walker($device, $snmp, '.1.0.8802.1.1') },
    %{ walker($device, $snmp, '.1.2.840.10006.300.43') },
    %{ walker($device, $snmp, '.1.3.6.1') },
    %{ walker($device, $snmp, '.1.3.111.2.802') },
  };
  # my %walk = walker($device, $snmp, '.1.3.6.1.2.1.2.2.1.6');   # 22 rows, i_mac/ifPhysAddress

  # something went wrong - error
  return $walk if ref {} ne ref $walk;

  # take the snmpwalk of the device which is numeric (no MIB translateObj),
  # resolve to MIB identifiers using netdisco-mibs, then store in SNMP::Info
  # instance cache

  my (%tables, %leaves, @realoids) = ((), (), ());
  OID: foreach my $orig_oid (keys %$walk) {
    my $oid = $orig_oid;
    my $idx = '';

    while (length($oid) and !exists $oidmap{$oid}) {
      $oid =~ s/\.(\d+)$//;
      $idx = ((defined $idx and length $idx) ? "${1}.${idx}" : $1);
    }

    if (exists $oidmap{$oid}) {
      $idx =~ s/^\.//;
      my $leaf = $oidmap{$oid};

      if ($idx eq 0) {
        push @realoids, $oid;
        $leaves{ $leaf } = $walk->{$orig_oid};
      }
      else {
        push @realoids, $oid if !exists $tables{ $leaf };
        $tables{ $leaf }->{$idx} = $walk->{$orig_oid};
      }

      # debug "snapshot $device - cached $oidmap{$oid}($idx) from $orig_oid";
      next OID;
    }

    debug "snapshot $device - missing OID $orig_oid in netdisco-mibs";
  }

  $snmp->_cache($_, $leaves{$_}) for keys %leaves;
  $snmp->_cache($_, $tables{$_}) for keys %tables;

  # add in any GLOBALS and FUNCS aliases which users have created in the
  # SNMP::Info device class, with binary copy of data so that it can be frozen

  my %cache   = %{ $snmp->cache() };
  my %funcs   = %{ $snmp->funcs() };
  my %globals = %{ $snmp->globals() };

  while (my ($alias, $leaf) = each %globals) {
    if (exists $cache{"_$leaf"} and !exists $cache{"_$alias"}) {
      $snmp->_cache($alias, $cache{"_$leaf"});
    }
  }

  while (my ($alias, $leaf) = each %funcs) {
    if (exists $cache{store}->{$leaf} and !exists $cache{store}->{$alias}) {
      $snmp->_cache($alias, dclone $cache{store}->{$leaf});
    }
  }

  # now for any other SNMP::Info method in GLOBALS or FUNCS which Netdisco
  # might call, but will not have data, we fake a cache entry to avoid
  # throwing errors

  # refresh the cache
  %cache = %{ $snmp->cache() };

  while (my $method = <DATA>) {
    $method =~ s/\s//g;
    next unless length $method and !exists $cache{"_$method"};

    $snmp->_cache($method, {}) if exists $funcs{$method};
    $snmp->_cache($method, '') if exists $globals{$method};
  }

  # put into the cache an oid ref to each leaf name
  # this allows rebuild of browser data from a frozen cache
  foreach my $oid (@realoids) {
      my $leaf = $oidmap{$oid} or next;
      $snmp->_cache($oid, $snmp->$leaf);
  }

  return 0;
}

# taken from SNMP::Info and adjusted to work on walks outside a single table
sub walker {
    my ($device, $snmp, $base) = @_;
    $base ||= '.1';

    my $sess = $snmp->session();
    return unless defined $sess;

    my $REPEATERS = 20;
    my $ver = $snmp->snmp_ver();

    # debug "snapshot $device - $base translated as $qual_leaf";
    my $var = SNMP::Varbind->new( [$base] );

    # So devices speaking SNMP v.1 are not supposed to give out
    # data from SNMP2, but most do.  Net-SNMP, being very precise
    # will tell you that the SNMP OID doesn't exist for the device.
    # They have a flag RetryNoSuch that is used for get() operations,
    # but not for getnext().  We set this flag normally, and if we're
    # using V1, let's try and fetch the data even if we get one of those.

    my %localstore = ();
    my $errornum   = 0;
    my %seen       = ();

    my $vars = [];
    my $bulkwalk_no
        = $snmp->can('bulkwalk_no') ? $snmp->bulkwalk_no() : 0;
    my $bulkwalk_on = defined $snmp->{BulkWalk} ? $snmp->{BulkWalk} : 1;
    my $can_bulkwalk = $bulkwalk_on && !$bulkwalk_no;
    my $repeaters = $snmp->{BulkRepeaters} || $REPEATERS;
    my $bulkwalk = $can_bulkwalk && $ver != 1;
    my $loopdetect
        = defined $snmp->{LoopDetect} ? $snmp->{LoopDetect} : 1;

    debug "snapshot $device - starting walk from $base";

    # Use BULKWALK if we can because its faster
    if ( $bulkwalk && @$vars == 0 ) {
        ($vars) = $sess->bulkwalk( 0, $repeaters, $var );
        if ( $sess->{ErrorNum} ) {
            debug "snapshot $device BULKWALK " . $sess->{ErrorStr};
            debug "snapshot $device disabling BULKWALK and trying again...";
            $vars = [];
            $bulkwalk = 0;
            $snmp->{BulkWalk} = 0;
            undef $sess->{ErrorNum};
            undef $sess->{ErrorStr};
        }
    }

    while ( !$errornum ) {
        if ($bulkwalk) {
            $var = shift @$vars or last;
        }
        else {
            # GETNEXT instead of BULKWALK
            # debug "snapshot $device GETNEXT $var";
            my @x = $sess->getnext($var);
            $errornum = $sess->{ErrorNum};
        }

        my $iid = $var->[1];
        my $val = $var->[2];
        my $oid = $var->[0] . (defined $iid ? ".${iid}" : '');

        # debug "snapshot $device reading $oid";
        # use DDP; p $var;

        unless ( defined $iid ) {
            error "snapshot $device not here";
            next;
        }

       # Check if last element, V2 devices may report ENDOFMIBVIEW even if
       # instance or object doesn't exist.
        if ( $val eq 'ENDOFMIBVIEW' ) {
            debug "snapshot $device : ENDOFMIBVIEW";
            last;
        }

        # Similarly for SNMPv1 - noSuchName return results in both $iid
        # and $val being empty strings.
        if ( $val eq '' and $iid eq '' ) {
            debug "snapshot $device : v1 noSuchName (1)";
            last;
        }

        # Another check for SNMPv1 - noSuchName return may results in an $oid
        # we've already seen and $val an empty string.  If we don't catch
        # this here we erroneously report a loop below.
        if ( defined $seen{$oid} and $seen{$oid} and $val eq '' ) {
            debug "snapshot $device : v1 noSuchName (2)";
            last;
        }

        if ($loopdetect) {
            # Check to see if we've already seen this IID (looping)
            if ( defined $seen{$oid} and $seen{$oid} ) {
                debug "snapshot $device : looping on $oid";
                shift @$vars;
                $var = shift @$vars or last;
                next;
            }
            else {
                $seen{$oid}++;
            }
        }

        if ( $val eq 'NOSUCHOBJECT' ) {
            error "snapshot $device :  NOSUCHOBJECT";
            next;
        }
        if ( $val eq 'NOSUCHINSTANCE' ) {
            error "snapshot $device :  NOSUCHINSTANCE";
            next;
        }

        # debug "snapshot $device - retreived $oid : $val";
        $localstore{$oid} = $val;
    }

    debug sprintf "snapshot $device - walked %d rows from $base",
      scalar keys %localstore;
    return \%localstore;
}

true;
