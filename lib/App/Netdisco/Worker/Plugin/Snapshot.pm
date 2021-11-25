package App::Netdisco::Worker::Plugin::Snapshot;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;
use App::Netdisco::Util::SNMP 'sortable_oid';
use Dancer::Plugin::DBIC 'schema';

use File::Spec::Functions qw(catdir catfile);
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

  my $save_browser = $job->extra;
  my $save_file = $job->port;

  # needed to avoid $var being returned with leafname and breaking loop checks
  $SNMP::use_numeric = 1;

  # might restore a cache if there's one on disk
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("snapshot failed: could not SNMP connect to $device");

  my %oidmap = getoidmap($device, $snmp);
  my %munges = get_munges($snmp);

  # only if not pseudo device
  if (not $device->is_pseudo) {
      my $walk_error = walk_and_store($device, $snmp, %oidmap);
      return $walk_error if $walk_error;
  }

  # load the cache
  my %cache = %{ $snmp->cache() };

  # finally, freeze the cache, then base64 encode, store in the DB,
  # optionally store browsing data, and optionally save file.

  if ($save_browser) {
      debug "snapshot $device - cacheing snapshot for browsing";
      my %seenoid = ();

      my @browser = map {{
        oid => $_,
        oid_parts => [ grep {length} (split m/\./, $_) ],
        leaf  => $oidmap{$_},
        munge => $munges{ $oidmap{$_} },
        value => do { my $m = $oidmap{$_}; encode_base64( nfreeze( [$snmp->$m] ) ); },
      }} sort {sortable_oid($a) cmp sortable_oid($b)}
         grep {not $seenoid{$_}++}
         grep {m/^\.1\.3\.6\.1/}
         map {s/^_//; $_}
         keys %cache;

      schema('netdisco')->txn_do(sub {
        my $gone = $device->oids->delete;
        debug sprintf 'snapshot %s - removed %d oids from db',
          $device->ip, $gone;
        $device->oids->populate(\@browser);
        debug sprintf 'snapshot %s - added %d new oids to db',
          $device->ip, scalar @browser;
      });
  }

  debug "snapshot $device - cacheing snapshot bundle";
  my $frozen = encode_base64( nfreeze( \%cache ) );
  $device->update_or_create_related('snapshot', {cache => $frozen});

  if ($save_file) {
      my $target_dir = catdir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'logs', 'snapshots');
      make_path($target_dir);
      my $target_file = catfile($target_dir, $device->ip);
      debug "snapshot $device - saving snapshot to $target_file";
      write_text($target_file, $frozen);
  }

  return Status->done(
    sprintf "Snapshot data captured from %s", $device->ip);
});

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# read in netdisco-mibs translation report and make an OID -> leafname map
sub getoidmap {
  my ($device, $snmp) = @_;
  debug "snapshot $device - loading netdisco-mibs object cache";

  my $home = (setting('mibhome') || catdir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'netdisco-mibs'));
  my @report = read_lines(catfile($home, qw(EXTRAS reports all_oids)), 'latin-1');

  my %oidmap = ();
  foreach my $line (@report) {
    my ($oid, $qual_leaf, $rest) = split m/,/, $line;
    next unless defined $oid and defined $qual_leaf;
    my ($mib, $leaf) = split m/::/, $qual_leaf;
    $oidmap{$oid} = $leaf;
  }

  debug sprintf "snapshot $device - loaded %d objects from netdisco-mibs",
    scalar keys %oidmap;
  return %oidmap;
}

sub get_munges {
  my $snmp = shift;
  my %munge_set = ();

  my %munge   = %{ $snmp->munge() };
  my %funcs   = %{ $snmp->funcs() };
  my %globals = %{ $snmp->globals() };

  while (my ($alias, $leaf) = each %globals) {
    $munge_set{$leaf} = subname($munge{$leaf}) if exists $munge{$leaf};
    $munge_set{$leaf} = subname($munge{$alias}) if exists $munge{$alias};
  }

  while (my ($alias, $leaf) = each %funcs) {
    $munge_set{$leaf} = subname($munge{$leaf}) if exists $munge{$leaf};
    $munge_set{$leaf} = subname($munge{$alias}) if exists $munge{$alias};
  }

  return %munge_set;
}

sub walk_and_store {
  my ($device, $snmp, %oidmap) = @_;

  my $walk = walker($device, $snmp, '.1.3.6.1');                 # 10205 rows
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
            error "snapshot $device BULKWALK " . $sess->{ErrorStr};
            return;
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
                return Status->error("Looping on: oid: $oid");
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

        # debug "snapshot $device - retreived $oid : $val";
        $localstore{$oid} = $val;
    }

    debug sprintf "snapshot $device - walked %d rows from $base",
      scalar keys %localstore;
    return \%localstore;
}

true;

__DATA__
agg_ports
at_paddr
bgp_peer_addr
bp_index
c_cap
c_id
c_if
c_ip
c_platform
c_port
cd11_mac
cd11_port
cd11_rateset
cd11_rxbyte
cd11_rxpkt
cd11_sigqual
cd11_sigstrength
cd11_ssid
cd11_txbyte
cd11_txpkt
cd11_txrate
cd11_uptime
class
contact
docs_if_cmts_cm_status_inet_address
dot11_cur_tx_pwr_mw
e_class
e_descr
e_fru
e_fwver
e_hwver
e_index
e_model
e_name
e_parent
e_pos
e_serial
e_swver
e_type
eigrp_peers
fw_mac
fw_port
has_topo
i_80211channel
i_alias
i_description
i_duplex
i_duplex_admin
i_err_disable_cause
i_faststart_enabled
i_ignore
i_lastchange
i_mac
i_mtu
i_name
i_speed
i_speed_admin
i_speed_raw
i_ssidbcast
i_ssidlist
i_ssidmac
i_stp_state
i_type
i_up
i_up_admin
i_vlan
i_vlan_membership
i_vlan_membership_untagged
i_vlan_type
interfaces
ip_index
ip_netmask
ipv6_addr
ipv6_addr_prefixlength
ipv6_index
ipv6_n2p_mac
ipv6_type
isis_peers
lldp_ipv6
lldp_media_cap
lldp_rem_model
lldp_rem_serial
lldp_rem_sw_rev
lldp_rem_vendor
location
model
name
ospf_peer_id
ospf_peers
peth_port_admin
peth_port_class
peth_port_ifindex
peth_port_power
peth_port_status
peth_power_status
peth_power_watts
ports
qb_fw_vlan
serial
serial1
snmpEngineID
snmpEngineTime
snmp_comm
snmp_ver
v_index
v_name
vrf_name
vtp_d_name
vtp_version
