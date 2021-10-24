package App::Netdisco::Worker::Plugin::Snapshot;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;

use File::Spec::Functions qw(catdir catfile);
use MIME::Base64 'encode_base64';
use File::Slurper qw(read_lines write_text);
use File::Path 'make_path';
use Storable qw(dclone nfreeze);
use DDP;

register_worker({ phase => 'check' }, sub {
  return Status->error('Missing device (-d).')
    unless defined shift->device;
  return Status->done('Snapshot is able to run');
});

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;
  my $save = $job->extra;

  # needed to avoid $var being returned with leafname and breaking loop checks
  $SNMP::use_numeric = 1;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("snapshot failed: could not SNMP connect to $device");

  my %oidmap = getoidmap($device, $snmp);
  my %walk = walker($device, $snmp, '.1.3.6.1');                 # 10205 rows
  # my %walk = walker($device, $snmp, '.1.3.6.1.2.1.2.2.1.6');   # 22 rows, i_mac/ifPhysAddress

  # take the snmpwalk of the device which is numeric (no MIB translateObj)
  # and resolve to MIB identifiers using the netdisco-mibs report
  # then store in SNMP::Info instance cache

  my (%tables, %leaves) = ((), ());
  OID: foreach my $orig_oid (keys %walk) {
    my $oid = $orig_oid;
    my $idx = '';

    while (length($oid) and !exists $oidmap{$oid}) {
      $oid =~ s/\.(\d+)$//;
      $idx = ($idx ? "${1}.${idx}" : $1);
    }

    if (exists $oidmap{$oid}) {
      $idx =~ s/^\.//;

      if ($idx eq 0) {
        $leaves{ $oidmap{$oid} } = $walk{$orig_oid};
      }
      else {
        $tables{ $oidmap{$oid} }->{$idx} = $walk{$orig_oid};
      }

      # debug "snapshot $device - cached $oidmap{$oid}($idx)";
      next OID;
    }

    debug "snapshot $device - missing OID $orig_oid in netdisco-mibs";
  }

  $snmp->_cache($_, $tables{$_}) for keys %tables;
  $snmp->_cache($_, $leaves{$_}) for keys %leaves;

  # we want to add in the GLOBALS and FUNCS aliases which users
  # have created in the SNMP::Info device class, with binary copy
  # of data so that it can be frozen

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

  # finally, freeze the cache, then base64 encode, store in our Job, and
  # optionally save file.

  # refresh the cache again
  %cache = %{ $snmp->cache() };

  my $frozen = encode_base64( nfreeze( \%cache ) );
  $job->subaction($frozen);

  if ($save) {
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
# takes about a second to run on my laptop
sub getoidmap {
  my ($device, $snmp, $oid) = @_;
  $oid ||= '.1';

  debug "snapshot $device - starting netdisco-mibs report parse";

  my $home = (setting('mibhome') || catdir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'netdisco-mibs'));
  my @report = read_lines(catfile($home, qw(EXTRAS reports all)), 'latin-1');

  my %oidmap = ();
  my $last_indent = 0;

  foreach my $line (@report) {
    my ($spaces, $leaf, $idx) = ($line =~ m/^(\s*)([-#\w]+)\((\d+)\)/);
    next unless defined $spaces and defined $leaf and defined $idx;
    my $this_indent = length($spaces);

    # update current OID
    if ($this_indent <= $last_indent) {
      my $step_back = (($last_indent - $this_indent) / 2);
      foreach (0 .. $step_back) { $oid =~ s/\.\d+$// }
    }
    $oid .= ".$idx";

    # store what we have just seen
    $oidmap{$oid} = $leaf;

    # and remember the indent
    $last_indent = $this_indent;
  }

  debug sprintf "snapshot $device - parsed %d items from netdisco-mibs report",
    scalar keys %oidmap;
  return %oidmap;
}

# taken from SNMP::Info and adjusted to work on walks outside a single table
sub walker {
    my ($device, $snmp, $base) = @_;
    $base ||= '.1';

    my $sess = $snmp->session();
    return unless defined $sess;

    my $REPEATERS = 20;
    my $ver  = $snmp->snmp_ver();

    # We want the qualified leaf name so that we can
    # specify the Module (MIB) in the case of private leaf naming
    # conflicts.  Example: ALTEON-TIGON-SWITCH-MIB::agSoftwareVersion
    # and ALTEON-CHEETAH-SWITCH-MIB::agSoftwareVersion
    # Third argument to translateObj specifies the Module prefix

    my $qual_leaf = SNMP::translateObj($base,0,1) || '';

    # We still want just the leaf since a SNMP get in the case of a
    # partial fetch may strip the Module portion upon return.  We need
    # the match to make sure we didn't leave the table during getnext
    # requests

    my ($leaf) = $qual_leaf =~ /::(.+)$/;

    # If we weren't able to translate, we'll only have an OID
    $leaf = $base unless defined $leaf;

    # debug "snapshot $device - $base translated as $qual_leaf";
    my $var = SNMP::Varbind->new( [$qual_leaf] );

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
            $sess->getnext($var);
            $errornum = $sess->{ErrorNum};
        }

        my $iid = $var->[1];
        my $val = $var->[2];
        my $oid = $var->[0] . (defined $iid ? ".${iid}" : '');

        # debug "snapshot $device reading $oid";
        # p $var;

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
                error "Looping on: oid:$oid. ";
                last;
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
    return %localstore;
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
