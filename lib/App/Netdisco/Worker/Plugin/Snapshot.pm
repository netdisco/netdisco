package App::Netdisco::Worker::Plugin::Snapshot;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;

use Data::Visitor::Tiny;
use File::Spec::Functions qw(catdir catfile);
use MIME::Base64 'encode_base64';
use File::Slurper 'read_lines';
use Storable 'nfreeze';
use DDP;

register_worker({ phase => 'check' }, sub {
  return Status->error('Missing device (-d).')
    unless defined shift->device;
  return Status->done('Snapshot is able to run');
});

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  # FIXME
  my $snmp = 1;#App::Netdisco::Transport::SNMP->reader_for($device)
#    or return Status->defer("snapshot failed: could not SNMP connect to $device");

  my $home = (setting('mibhome') || catdir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'netdisco-mibs'));
  my @report = read_lines(catfile($home, qw(EXTRAS reports all)), 'latin-1')
    or return Status->error("snapshot failed to read netdisco-mibs report file");

  my $oid = '.1';
  my $last_indent = 0;
  my %oidmap = ();

  foreach my $line (@report) {
    my ($spaces, $leaf, $idx) = ($line =~ m/^(\s*)([-\w]+)\((\d+)\)/);
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

  #p %oidmap;
  # FIXME
  return Status->done(
    sprintf "Snapshot data from %s", $device->ip);

  foreach my $method (qw/
    i_mac
    snmpEngineID
    ifName
    SNMP_VIEW_BASED_ACM_MIB__vacmViewTreeFamilyStorageType
    /) {

      debug sprintf ' [%s] snapshot - requesting %s', $device->ip, $method;
      eval { $snmp->$method() };
  }

  my $cache = $snmp->cache();
  visit( $cache, sub {
      my ($key, $valueref) = @_;
      ($$valueref = encode_base64( $$valueref )) =~ s/\n$// if defined $_ and ref $_ eq q{};
  });
  p $cache;

  $job->subaction( encode_base64( nfreeze( $cache ) ) );
  return Status->done(
    sprintf "Snapshot data captured from %s", $device->ip);
});

true;
__END__
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
      load_uptime
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
      set_contact
      set_i_alias
      set_i_up_admin
      set_location
      set_peth_port_admin
      snmpEngineID
      snmpEngineTime
      snmp_comm
      snmp_ver
      v_index
      v_name
      vrf_name
      vtp_d_name
      vtp_version
