package App::Netdisco::Worker::Plugin::GatherReplay;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;

use Data::Visitor::Tiny;
use MIME::Base64 'encode_base64';
use DDP;

register_worker({ phase => 'check' }, sub {
  return Status->error('Missing device (-d).')
    unless defined shift->device;
  return Status->done('Gather is able to run');
});

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("gather failed: could not SNMP connect to $device");

  my $munge = {
    _snmpEngineID => sub { unpack('H*', (shift || '')) },
    i_mac => sub { my $h = shift; return { map {( $_ => $snmp->munge_mac($h->{$_}) )} keys %$h } },
  };

  foreach my $method (qw/
    i_mac
    snmpEngineID
    /) {

      debug sprintf ' [%s] gather - requesting %s', $device->ip, $method;
      eval { $snmp->$method() };
  }

  my $cache = $snmp->cache();
  visit( $cache, sub {
      my ($key, $valueref) = @_;
      ($$valueref = encode_base64( $$valueref )) =~ s/\n$// if defined $_ and ref $_ eq q{};
  });
  p $cache;

  return Status->done(
    sprintf "Gathered Replay data from %s", $device->ip);
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
