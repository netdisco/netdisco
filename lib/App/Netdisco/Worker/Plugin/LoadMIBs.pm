package App::Netdisco::Worker::Plugin::LoadMIBs;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Dancer::Plugin::DBIC 'schema';

use Storable 'thaw';
use MIME::Base64 qw/encode_base64 decode_base64/;
use File::Spec::Functions qw(splitdir catfile catdir);
use File::Slurper qw(read_lines write_text);

use App::Netdisco::Util::Device 'get_device';
use App::Netdisco::Util::Snapshot 'make_snmpwalk_browsable';
# use DDP;

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;

  my $vendor = $job->extra;
  debug sprintf 'loadmibs - loading netdisco-mibs object cache%s',
    ($vendor ? (sprintf ' for vendor "%s"', $vendor) : '');

  my $home = (setting('mibhome') || catdir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'netdisco-mibs'));
  my $reports = catdir( $home, 'EXTRAS', 'reports' );
  my @maps = map  { (splitdir($_))[-1] }
             grep { ! m/^(?:EXTRAS)$/ }
             grep { ! m/\./ }
             grep { -f }
             glob (catfile( $reports, '*_oids' ));

  my @report = ();
  if ($vendor) {
      push @report, read_lines( catfile( $reports, "${vendor}_oids" ), 'latin-1' );
  }
  else {
      push @report, read_lines( catfile( $reports, $_ ), 'latin-1' )
        for (qw(rfc_oids net-snmp_oids cisco_oids), @maps);
  }
  
  my @browser = ();
  my %children = ();
  my %seenoid = ();

  foreach my $line (@report) {
    my ($oid, $qual_leaf, $type, $access, $index, $status, $enum, $descr) = split m/,/, $line, 8;
    next unless defined $oid and defined $qual_leaf;
    next if ++$seenoid{$oid} > 1;

    my ($mib, $leaf) = split m/::/, $qual_leaf;
    my @oid_parts = grep {length} (split m/\./, $oid);
    ++$children{ join '.', '', @oid_parts[0 .. (@oid_parts - 2)] }
      if scalar @oid_parts > 1;

    push @browser, {
      oid    => $oid,
      oid_parts => [ @oid_parts ],
      mib    => $mib,
      leaf   => $leaf,
      type   => $type,
      access => $access,
      index  => [($index ? (split m/:/, $index) : ())],
      status => $status,
      enum   => [($enum  ? (split m/:/, $enum ) : ())],
      descr  => $descr,
    };
  }

  foreach my $row (@browser) {
    $row->{num_children} = $children{ $row->{oid} } || 0;
  }

  debug sprintf "loadmibs - loaded %d objects from netdisco-mibs",
    scalar @browser;

  schema('netdisco')->txn_do(sub {
    my $gone = schema('netdisco')->resultset('SNMPObject')->delete;
    debug sprintf 'loadmibs - removed %d oids', $gone;
    schema('netdisco')->resultset('SNMPObject')->populate(\@browser);
    debug sprintf 'loadmibs - added %d new oids', scalar @browser;
  });

  # promote snapshots prior to loadmibs to be browsable
  schema('netdisco')->txn_do(sub {
    my @devices = schema('netdisco')
          ->resultset('DeviceBrowser')
          ->search({ -bool => \q{ array_length(oid_parts, 1) IS NULL } })
          ->distinct('ip')->get_column('ip')->all;

    foreach my $ip (@devices) {
        my $dev = get_device($ip);
        next unless $dev->in_storage;
        debug sprintf 'loadmibs - promoting snapshot for %s to be browsable', $dev->ip;
        make_snmpwalk_browsable($dev);
    }
  });

  # legacy snapshot upgrade
  schema('netdisco')->txn_do(sub {
    my $legacy_rs = schema('netdisco')
          ->resultset('DeviceBrowser')
          ->search({ -bool => \q{ jsonb_typeof(value) != 'array' } });

    if ($legacy_rs->count) {
        my @rows = $legacy_rs->hri->all;
        my $gone = $legacy_rs->delete;
        
        # the legacy looks like encode_base64( nfreeze( [$data] ) )
        foreach my $row (@rows) {
            my $value = (@{ thaw( decode_base64( from_json($row->{value}) ) ) })[0];
            $value = (ref {} eq ref $value)
              ? { map {($_ => (defined $value->{$_} ? encode_base64($value->{$_}, '') : undef))}
                  keys %$value }
              : (defined $value ? encode_base64($value, '') : undef);
            $row->{value} = to_json([$value]);
        }

        schema('netdisco')->resultset('DeviceBrowser')->populate(\@rows);
        debug sprintf 'loadmibs - updated %d legacy snapshot rows', scalar @rows;
    }
  });

  return Status->done('Loaded MIBs');
});

true;

__DATA__
ad_lag_ports	SNMP::Info::munge_port_list
adminAgentPhysAddress	SNMP::Info::munge_mac
adminAgentPhysAddress.0	SNMP::Info::munge_mac
ag_mod2_type	SNMP::Info::munge_e_type
ag_mod_type	SNMP::Info::munge_e_type
agentInterfaceMacAddress	SNMP::Info::munge_mac
aipAMAPRemHostname	SNMP::Info::munge_null
airespace_ap_ethermac	SNMP::Info::munge_mac
airespace_ap_mac	SNMP::Info::munge_mac
airespace_bl_mac	SNMP::Info::munge_mac
airespace_if_mac	SNMP::Info::munge_mac
airespace_sta_mac	SNMP::Info::munge_mac
alHardwareFan1RpmAlarm	SNMP::Info::Layer3::Altiga::munge_alarm
alHardwareFan2RpmAlarm	SNMP::Info::Layer3::Altiga::munge_alarm
alHardwareFan3RpmAlarm	SNMP::Info::Layer3::Altiga::munge_alarm
alHardwarePs1Voltage3vAlarm	SNMP::Info::Layer3::Altiga::munge_alarm
alHardwarePs1Voltage5vAlarm	SNMP::Info::Layer3::Altiga::munge_alarm
alHardwarePs2Voltage3vAlarm	SNMP::Info::Layer3::Altiga::munge_alarm
alHardwarePs2Voltage5vAlarm	SNMP::Info::Layer3::Altiga::munge_alarm
amap_rem_sysname	SNMP::Info::munge_null
ap_if_mac	SNMP::Info::munge_mac
aruba_ap_bssid_ssid	SNMP::Info::munge_null
aruba_ap_fqln	SNMP::Info::Layer3::Aruba::munge_aruba_fqln
aruba_ap_type	SNMP::Info::munge_e_type
aruba_card_type	SNMP::Info::munge_e_type
aruba_user_bssid	SNMP::Info::munge_mac
atPhysAddress	SNMP::Info::munge_mac
at_paddr	SNMP::Info::munge_mac
awcIfPhysAddress	SNMP::Info::munge_mac
awc_mac	SNMP::Info::munge_mac
b_mac	SNMP::Info::munge_mac
bs_mac	SNMP::Info::munge_mac
bsnAPDot3MacAddress	SNMP::Info::munge_mac
bsnAPEthernetMacAddress	SNMP::Info::munge_mac
bsnBlackListClientMacAddress	SNMP::Info::munge_mac
bsnMobileStationAPMacAddr	SNMP::Info::munge_mac
bsnMobileStationMacAddress	SNMP::Info::munge_mac
bsnMobileStationPacketsReceived	SNMP::Info::Airespace::munge_64bits
bsnMobileStationPacketsSent	SNMP::Info::Airespace::munge_64bits
cDot11ClientCurrentTxRateSet	SNMP::Info::Layer2::Aironet::munge_cd11_txrate
cDot11ClientDataRateSet	SNMP::Info::Layer2::Aironet::munge_cd11_txrate
cInetNetToMediaPhysAddress	SNMP::Info::IPv6::munge_physaddr
cLApIfMacAddress	SNMP::Info::munge_mac
c_id	SNMP::Info::Layer2::HP::munge_hp_c_id
c_inet_phys_addr	SNMP::Info::IPv6::munge_physaddr
cbgpPeer2LastError	SNMP::Info::munge_octet2hex
cbgpPeer2LocalAddr	SNMP::Info::munge_inetaddress
cd11_proto	SNMP::Info::Layer2::Airespace::munge_cd11_proto
cd11_rateset	SNMP::Info::Layer2::Aironet::munge_cd11_txrate
cd11_rxpkt	SNMP::Info::Airespace::munge_64bits
cd11_ssid	SNMP::Info::munge_null
cd11_txpkt	SNMP::Info::Airespace::munge_64bits
cd11_txrate	SNMP::Info::Layer2::Aironet::munge_cd11_txrate
cd11n_ch_bw	SNMP::Info::Layer2::Airespace::munge_cd11n_ch_bw
cdot11MbssidIfMacAddress	SNMP::Info::munge_mac
cdpCacheCapabilities	SNMP::Info::munge_bits
cdpCachePlatform	SNMP::Info::munge_null
cdpCachePowerConsumption	SNMP::Info::CDP::munge_power
cdpCacheVTPMgmtDomain	SNMP::Info::munge_null
cdpCacheVersion	SNMP::Info::munge_null
cdp_capabilities	SNMP::Info::munge_bits
cdp_domain	SNMP::Info::munge_null
cdp_ip	SNMP::Info::munge_ip
cdp_platform	SNMP::Info::munge_null
cdp_power	SNMP::Info::CDP::munge_power
cdp_ver	SNMP::Info::munge_null
cisco_bgp_peer2_lasterror	SNMP::Info::munge_octet2hex
cisco_bgp_peer2_localaddr	SNMP::Info::munge_inetaddress
clagAggPortListInterfaceIndexList	SNMP::Info::CiscoAgg::munge_port_ifindex
clagAggPortListPorts	SNMP::Info::munge_port_list
cldHtDot11nChannelBandwidth	SNMP::Info::Layer2::Airespace::munge_cd11n_ch_bw
cldcClientDataRateSet	SNMP::Info::Layer2::Airespace::munge_cd11_rateset
cldcClientProtocol	SNMP::Info::Layer2::Airespace::munge_cd11_proto
cpsIfSecureLastMacAddress	SNMP::Info::munge_mac
cps_i_mac	SNMP::Info::munge_mac
dot11MACAddress	SNMP::Info::munge_mac
dot11StationID	SNMP::Info::munge_mac
dot11StationID.2	SNMP::Info::munge_mac
dot11_mac	SNMP::Info::munge_mac
dot11_sta_id	SNMP::Info::munge_mac
dot1dBaseBridgeAddress	SNMP::Info::munge_mac
dot1dBaseBridgeAddress.0	SNMP::Info::munge_mac
dot1dStaticAddress	SNMP::Info::munge_mac
dot1dStpDesignatedRoot	SNMP::Info::munge_prio_mac
dot1dStpPortDesignatedBridge	SNMP::Info::munge_prio_mac
dot1dStpPortDesignatedPort	SNMP::Info::munge_prio_port
dot1dStpPortDesignatedRoot	SNMP::Info::munge_prio_mac
dot1dTpFdbAddress	SNMP::Info::munge_mac
dot1dTpFdbPort	SNMP::Info::munge_mac
dot1qVlanCurrentEgressPorts	SNMP::Info::munge_port_list
dot1qVlanCurrentUntaggedPorts	SNMP::Info::munge_port_list
dot1qVlanForbiddenEgressPorts	SNMP::Info::munge_port_list
dot1qVlanStaticEgressPorts	SNMP::Info::munge_port_list
dot1qVlanStaticUntaggedPorts	SNMP::Info::munge_port_list
dot1xAuthLastEapolFrameSource	SNMP::Info::munge_mac
dot1xPaePortCapabilities	SNMP::Info::CiscoPortSecurity::munge_pae_capabilities
dot3StatsDuplexStatus	SNMP::Info::EtherLike::munge_el_duplex
dot3adAggPortListPorts	SNMP::Info::munge_port_list
e_class	SNMP::Info::Layer3::Timetra::munge_tmnx_e_class
e_containers_type	SNMP::Info::munge_e_type
e_contents_type	SNMP::Info::munge_e_type
e_swver	SNMP::Info::Layer3::Timetra::munge_tmnx_e_swver
e_type	SNMP::Info::munge_e_type
edp_rem_sysname	SNMP::Info::munge_null
el_duplex	SNMP::Info::EtherLike::munge_el_duplex
entPhysicalVendorType	SNMP::Info::munge_e_type
ex_fw_mac	SNMP::Info::munge_mac
ex_stp_i_mac	SNMP::Info::munge_prio_mac
ex_vlan_tagged	SNMP::Info::munge_port_list
ex_vlan_untagged	SNMP::Info::munge_port_list
extremeEdpNeighborName	SNMP::Info::munge_null
extremeFanOperational	SNMP::Info::Layer3::Extreme::munge_true_ok
extremeFdbMacFdbMacAddress	SNMP::Info::munge_mac
extremePowerSupplyStatus	SNMP::Info::Layer3::Extreme::munge_power_stat
extremePowerSupplyStatus.1	SNMP::Info::Layer3::Extreme::munge_power_stat
extremePowerSupplyStatus.2	SNMP::Info::Layer3::Extreme::munge_power_stat
extremePrimaryPowerOperational	SNMP::Info::Layer3::Extreme::munge_true_ok
extremePrimaryPowerOperational.0	SNMP::Info::Layer3::Extreme::munge_true_ok
extremeRedundantPowerStatus	SNMP::Info::Layer3::Extreme::munge_power_stat
extremeRedundantPowerStatus.0	SNMP::Info::Layer3::Extreme::munge_power_stat
extremeStpDomainBridgeId	SNMP::Info::munge_prio_mac
extremeStpDomainDesignatedRoot	SNMP::Info::munge_prio_mac
extremeStpPortDesignatedBridge	SNMP::Info::munge_prio_mac
extremeStpPortDesignatedPort	SNMP::Info::munge_prio_port
extremeStpPortDesignatedRoot	SNMP::Info::munge_prio_mac
extremeVlanOpaqueTaggedPorts	SNMP::Info::munge_port_list
extremeVlanOpaqueUntaggedPorts	SNMP::Info::munge_port_list
fan1_alarm	SNMP::Info::Layer3::Altiga::munge_alarm
fan2_alarm	SNMP::Info::Layer3::Altiga::munge_alarm
fan3_alarm	SNMP::Info::Layer3::Altiga::munge_alarm
fan_state	SNMP::Info::Layer3::Extreme::munge_true_ok
fdp_capabilities	SNMP::Info::munge_bits
fdp_ip	SNMP::Info::munge_ip
fw_mac	SNMP::Info::munge_mac
fw_mac2	SNMP::Info::munge_mac
fw_port	SNMP::Info::munge_mac
hpSwitchBaseMACAddress	SNMP::Info::munge_mac
hpSwitchBaseMACAddress.0	SNMP::Info::munge_mac
hwPoePortEnable	SNMP::Info::Layer3::Huawei::munge_hw_peth_admin
hwPoePortPdClass	SNMP::Info::Layer3::Huawei::munge_hw_peth_class
hwPoePortPowerStatus	SNMP::Info::Layer3::Huawei::munge_hw_peth_status
hwPoeSlotConsumingPower	SNMP::Info::Layer3::Huawei::munge_hw_peth_power
hwPoeSlotMaximumPower	SNMP::Info::Layer3::Huawei::munge_hw_peth_power
hw_peth_port_admin	SNMP::Info::Layer3::Huawei::munge_hw_peth_admin
hw_peth_port_class	SNMP::Info::Layer3::Huawei::munge_hw_peth_class
hw_peth_port_status	SNMP::Info::Layer3::Huawei::munge_hw_peth_status
i6_n2p_phys_addr	SNMP::Info::munge_mac
i_duplex	SNMP::Info::Layer2::Nexans::munge_i_duplex
i_duplex_admin	SNMP::Info::Layer2::Nexans::munge_i_duplex_admin
i_mac	SNMP::Info::munge_mac
i_mac2	SNMP::Info::munge_mac
i_octet_in64	SNMP::Info::munge_counter64
i_octet_out64	SNMP::Info::munge_counter64
i_pkts_bcast_in64	SNMP::Info::munge_counter64
i_pkts_bcast_out64	SNMP::Info::munge_counter64
i_pkts_multi_out64	SNMP::Info::munge_counter64
i_pkts_mutli_in64	SNMP::Info::munge_counter64
i_pkts_ucast_in64	SNMP::Info::munge_counter64
i_pkts_ucast_out64	SNMP::Info::munge_counter64
i_speed	SNMP::Info::munge_speed
i_speed_high	SNMP::Info::munge_highspeed
i_up	SNMP::Info::munge_i_up
ieee8021QBridgeVlanCurrentEgressPorts	SNMP::Info::munge_port_list
ieee8021QBridgeVlanCurrentUntaggedPorts	SNMP::Info::munge_port_list
ieee8021QBridgeVlanForbiddenEgressPorts	SNMP::Info::munge_port_list
ieee8021QBridgeVlanStaticEgressPorts	SNMP::Info::munge_port_list
ieee8021QBridgeVlanStaticUntaggedPorts	SNMP::Info::munge_port_list
ifHCInBroadcastPkts	SNMP::Info::munge_counter64
ifHCInOctets	SNMP::Info::munge_counter64
ifHCInUcastPkts	SNMP::Info::munge_counter64
ifHCOutBroadcastPkts	SNMP::Info::munge_counter64
ifHCOutMulticastPkts	SNMP::Info::munge_counter64
ifHCOutOctets	SNMP::Info::munge_counter64
ifHCOutUcastPkts	SNMP::Info::munge_counter64
ifHighSpeed	SNMP::Info::munge_highspeed
ifMauAutoNegCapAdvertised	SNMP::Info::MAU::munge_int2bin
ifMauAutoNegCapReceived	SNMP::Info::MAU::munge_int2bin
ifMauTypeList	SNMP::Info::MAU::munge_int2bin
ifOperStatus	SNMP::Info::munge_i_up
ifPhysAddress	SNMP::Info::munge_mac
ifPhysAddress.1	SNMP::Info::munge_mac
ifPhysAddress.2	SNMP::Info::munge_mac
ifSpeed	SNMP::Info::munge_speed
ip	SNMP::Info::munge_ip
ipNetToMediaPhysAddress	SNMP::Info::munge_mac
ipNetToPhysicalPhysAddress	SNMP::Info::munge_mac
ip_n2p_phys_addr	SNMP::Info::munge_mac
ipv6NetToMediaPhysAddress	SNMP::Info::munge_mac
iqb_cv_egress	SNMP::Info::munge_port_list
iqb_cv_untagged	SNMP::Info::munge_port_list
iqb_v_egress	SNMP::Info::munge_port_list
iqb_v_fbdn_egress	SNMP::Info::munge_port_list
iqb_v_untagged	SNMP::Info::munge_port_list
jnxContainersType	SNMP::Info::munge_e_type
jnxContentsType	SNMP::Info::munge_e_type
lag_members	SNMP::Info::CiscoAgg::munge_port_ifindex
lag_ports	SNMP::Info::munge_port_list
layers	SNMP::Info::munge_dec2bin
lldpInfoRemoteDevicesSystemCapEnabled	SNMP::Info::munge_bits
lldpInfoRemoteDevicesSystemDescription	SNMP::Info::munge_null
lldpInfoRemoteDevicesSystemName	SNMP::Info::munge_null
lldpLocPortDesc	SNMP::Info::munge_null
lldpLocPortId	SNMP::Info::munge_null
lldpLocSysCapEnabled	SNMP::Info::munge_bits
lldpLocSysDesc	SNMP::Info::munge_null
lldpLocSysName	SNMP::Info::munge_null
lldpRemSysCapEnabled	SNMP::Info::munge_bits
lldpRemSysCapSupported	SNMP::Info::munge_bits
lldpRemSysDesc	SNMP::Info::munge_null
lldpRemSysName	SNMP::Info::munge_null
lldpXMedRemAssetID	SNMP::Info::munge_null
lldpXMedRemCapCurrent	SNMP::Info::munge_bits
lldpXMedRemCapSupported	SNMP::Info::munge_bits
lldpXMedRemFirmwareRev	SNMP::Info::munge_null
lldpXMedRemHardwareRev	SNMP::Info::munge_null
lldpXMedRemMfgName	SNMP::Info::munge_null
lldpXMedRemModelName	SNMP::Info::munge_null
lldpXMedRemSerialNum	SNMP::Info::munge_null
lldpXMedRemSoftwareRev	SNMP::Info::munge_null
lldp_lport_desc	SNMP::Info::munge_null
lldp_lport_id	SNMP::Info::munge_null
lldp_rem_asset	SNMP::Info::munge_null
lldp_rem_cap_spt	SNMP::Info::munge_bits
lldp_rem_fw_rev	SNMP::Info::munge_null
lldp_rem_hw_rev	SNMP::Info::munge_null
lldp_rem_media_cap	SNMP::Info::munge_bits
lldp_rem_media_cap_spt	SNMP::Info::munge_bits
lldp_rem_model	SNMP::Info::munge_null
lldp_rem_port_desc	SNMP::Info::munge_null
lldp_rem_serial	SNMP::Info::munge_null
lldp_rem_sw_rev	SNMP::Info::munge_null
lldp_rem_sys_cap	SNMP::Info::munge_bits
lldp_rem_sysdesc	SNMP::Info::munge_null
lldp_rem_sysname	SNMP::Info::munge_null
lldp_rem_vendor	SNMP::Info::munge_null
lldp_sys_cap	SNMP::Info::munge_bits
lldp_sysdesc	SNMP::Info::munge_null
lldp_sysname	SNMP::Info::munge_null
m_ports_status	SNMP::Info::CiscoStack::munge_port_status
mac	SNMP::Info::munge_mac
mac_table	SNMP::Info::munge_mac
mau_autorec	SNMP::Info::MAU::munge_int2bin
mau_autosent	SNMP::Info::MAU::munge_int2bin
mau_type	SNMP::Info::MAU::munge_int2bin
mbss_mac_addr	SNMP::Info::munge_mac
modulePortStatus	SNMP::Info::CiscoStack::munge_port_status
n2p_paddr	SNMP::Info::munge_mac
nUserApBSSID	SNMP::Info::munge_mac
nsIfMAC	SNMP::Info::munge_mac
nsIpArpMac	SNMP::Info::munge_mac
ns_at_paddr	SNMP::Info::munge_mac
ns_ch_type	SNMP::Info::munge_e_type
ns_com_type	SNMP::Info::munge_e_type
ns_grp_type	SNMP::Info::NortelStack::munge_ns_grp_type
ns_i_mac	SNMP::Info::munge_mac
ns_store_type	SNMP::Info::munge_e_type
ntwsApStatRadioServBssid	SNMP::Info::munge_mac
ntwsApStatRadioStatusBaseMac	SNMP::Info::munge_mac
nwss2300_apif_bssid	SNMP::Info::munge_mac
nwss2300_apif_mac	SNMP::Info::munge_mac
old_at_paddr	SNMP::Info::munge_mac
p_duplex_admin	SNMP::Info::munge_bits
pae_i_capabilities	SNMP::Info::CiscoPortSecurity::munge_pae_capabilities
pae_i_last_eapol_frame_source	SNMP::Info::munge_mac
peth_power_consumption	SNMP::Info::Layer3::Huawei::munge_hw_peth_power
peth_power_watts	SNMP::Info::Layer3::Huawei::munge_hw_peth_power
portCpbDuplex	SNMP::Info::munge_bits
portLinkState	SNMP::Info::Layer2::Nexans::munge_i_duplex
portSpeedDuplexSetup	SNMP::Info::Layer2::Nexans::munge_i_duplex_admin
ps1_3v_alarm	SNMP::Info::Layer3::Altiga::munge_alarm
ps1_5v_alarm	SNMP::Info::Layer3::Altiga::munge_alarm
ps1_status_new	SNMP::Info::Layer3::Extreme::munge_power_stat
ps1_status_old	SNMP::Info::Layer3::Extreme::munge_true_ok
ps2_3v_alarm	SNMP::Info::Layer3::Altiga::munge_alarm
ps2_5v_alarm	SNMP::Info::Layer3::Altiga::munge_alarm
ps2_status_new	SNMP::Info::Layer3::Extreme::munge_power_stat
ps2_status_old	SNMP::Info::Layer3::Extreme::munge_power_stat
qb_cv_egress	SNMP::Info::munge_port_list
qb_cv_untagged	SNMP::Info::munge_port_list
qb_v_egress	SNMP::Info::munge_port_list
qb_v_fbdn_egress	SNMP::Info::munge_port_list
qb_v_untagged	SNMP::Info::munge_port_list
rc2kChassisBaseMacAddr	SNMP::Info::munge_mac
rc2kCpuEthernetPortMgmtMacAddr	SNMP::Info::munge_mac
rcMltPortMembers	SNMP::Info::munge_port_list
rcStgBridgeAddress	SNMP::Info::munge_mac
rcStgDesignatedRoot	SNMP::Info::munge_prio_mac
rcStgPortDesignatedBridge	SNMP::Info::munge_prio_mac
rcStgPortDesignatedPort	SNMP::Info::munge_prio_port
rcStgPortDesignatedRoot	SNMP::Info::munge_prio_mac
rcVlanMacAddress	SNMP::Info::munge_mac
rcVlanNotAllowToJoin	SNMP::Info::munge_port_list
rcVlanPortMembers	SNMP::Info::munge_port_list
rc_base_mac	SNMP::Info::munge_mac
rc_cpu_mac	SNMP::Info::munge_mac
rc_mlt_ports	SNMP::Info::munge_port_list
rc_stp_i_mac	SNMP::Info::munge_mac
rc_stp_i_root	SNMP::Info::munge_prio_mac
rc_stp_p_bridge	SNMP::Info::munge_prio_mac
rc_stp_p_port	SNMP::Info::munge_prio_port
rc_stp_p_root	SNMP::Info::munge_prio_mac
rc_vlan_mac	SNMP::Info::munge_mac
rc_vlan_members	SNMP::Info::munge_port_list
rc_vlan_no_join	SNMP::Info::munge_port_list
rndBasePhysicalAddress	SNMP::Info::munge_mac
rptrAddrTrackNewLastSrcAddress	SNMP::Info::munge_mac
rptr_last_src	SNMP::Info::munge_mac
s3000_topo_mac	SNMP::Info::munge_mac
s3EnetShowNodesMacAddress	SNMP::Info::munge_mac
s3EnetTopNmmMacAddr	SNMP::Info::munge_mac
s5ChasComType	SNMP::Info::munge_e_type
s5ChasGrpType	SNMP::Info::NortelStack::munge_ns_grp_type
s5ChasStoreType	SNMP::Info::munge_e_type
s5ChasType	SNMP::Info::munge_e_type
s5CmSNodeMacAddr	SNMP::Info::munge_mac
s5EnMsTopNmmEnhancedMacAddr	SNMP::Info::munge_mac
s5EnMsTopNmmMacAddr	SNMP::Info::munge_mac
snAgentConfigModule2Type	SNMP::Info::munge_e_type
snAgentConfigModuleType	SNMP::Info::munge_e_type
snFdpCacheAddress	SNMP::Info::munge_ip
snFdpCacheCapabilities	SNMP::Info::munge_bits
snPortStpPortDesignatedBridge	SNMP::Info::munge_prio_mac
snPortStpPortDesignatedPort	SNMP::Info::munge_prio_port
snPortStpPortDesignatedRoot	SNMP::Info::munge_prio_mac
snVLanByPortBaseBridgeAddress	SNMP::Info::munge_mac
snVLanByPortStpDesignatedRoot	SNMP::Info::munge_prio_mac
sonmp_topo_e_mac	SNMP::Info::munge_mac
sonmp_topo_mac	SNMP::Info::munge_mac
std_at_paddr	SNMP::Info::munge_mac
stp_i_mac	SNMP::Info::munge_mac
stp_i_root	SNMP::Info::munge_prio_mac
stp_p_bridge	SNMP::Info::munge_prio_mac
stp_p_port	SNMP::Info::munge_prio_port
stp_p_root	SNMP::Info::munge_prio_mac
stp_root	SNMP::Info::munge_prio_mac
stpxSMSTConfigDigest	SNMP::Info::CiscoStpExtensions::oct2str
stpx_mst_config_digest	SNMP::Info::CiscoStpExtensions::oct2str
sysExtCardType	SNMP::Info::munge_e_type
sysServices	SNMP::Info::munge_dec2bin
tmnxChassisFanOperStatus	SNMP::Info::Layer3::Timetra::munge_tmnx_state
tmnxChassisPowerSupply1Status	SNMP::Info::Layer3::Timetra::munge_tmnx_state
tmnxChassisPowerSupply2Status	SNMP::Info::Layer3::Timetra::munge_tmnx_state
tmnxHwClass	SNMP::Info::Layer3::Timetra::munge_tmnx_e_class
tmnxHwSoftwareCodeVersion	SNMP::Info::Layer3::Timetra::munge_tmnx_e_swver
tmnxLldpRemSysCapEnabled	SNMP::Info::munge_bits
tmnxLldpRemSysCapSupported	SNMP::Info::munge_bits
tmnxLldpRemSysDesc	SNMP::Info::munge_null
tmnxLldpRemSysName	SNMP::Info::munge_null
tmnx_fan_state	SNMP::Info::Layer3::Timetra::munge_tmnx_state
tmnx_ps1_state	SNMP::Info::Layer3::Timetra::munge_tmnx_state
tmnx_ps2_state	SNMP::Info::Layer3::Timetra::munge_tmnx_state
trapeze_apif_bssid	SNMP::Info::munge_mac
trapeze_apif_mac	SNMP::Info::munge_mac
trpzApStatRadioServBssid	SNMP::Info::munge_mac
trpzApStatRadioStatusBaseMac	SNMP::Info::munge_mac
wfHwBabyBdSerialNumber	SNMP::Info::Layer3::BayRS::munge_wf_serial
wfHwBootPromRev	SNMP::Info::Layer3::BayRS::munge_hw_rev
wfHwDaughterBdSerialNumber	SNMP::Info::Layer3::BayRS::munge_wf_serial
wfHwDiagPromRev	SNMP::Info::Layer3::BayRS::munge_hw_rev
wfHwModDaughterBd1SerialNumber	SNMP::Info::Layer3::BayRS::munge_wf_serial
wfHwModDaughterBd2SerialNumber	SNMP::Info::Layer3::BayRS::munge_wf_serial
wfHwModSerialNumber	SNMP::Info::Layer3::BayRS::munge_wf_serial
wfHwModuleModSerialNumber	SNMP::Info::Layer3::BayRS::munge_wf_serial
wfHwMotherBdSerialNumber	SNMP::Info::Layer3::BayRS::munge_wf_serial
wf_hw_bb_ser	SNMP::Info::Layer3::BayRS::munge_wf_serial
wf_hw_boot	SNMP::Info::Layer3::BayRS::munge_hw_rev
wf_hw_db_ser	SNMP::Info::Layer3::BayRS::munge_wf_serial
wf_hw_diag	SNMP::Info::Layer3::BayRS::munge_hw_rev
wf_hw_md1_ser	SNMP::Info::Layer3::BayRS::munge_wf_serial
wf_hw_md2_ser	SNMP::Info::Layer3::BayRS::munge_wf_serial
wf_hw_mm_ser	SNMP::Info::Layer3::BayRS::munge_wf_serial
wf_hw_mobo_ser	SNMP::Info::Layer3::BayRS::munge_wf_serial
wf_hw_mod_ser	SNMP::Info::Layer3::BayRS::munge_wf_serial
wlanAPESSID	SNMP::Info::munge_null
wlanAPFQLN	SNMP::Info::Layer3::Aruba::munge_aruba_fqln
wlanAPModel	SNMP::Info::munge_e_type
wlanStaAccessPointESSID	SNMP::Info::munge_null
wlsxSysExtSwitchBaseMacaddress	SNMP::Info::munge_mac