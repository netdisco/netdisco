package App::Netdisco::Util::Snapshot;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::SNMP qw/get_mibdirs sortable_oid/;

use File::Spec::Functions qw/catdir catfile/;
use MIME::Base64 qw/encode_base64 decode_base64/;
use File::Slurper 'read_lines';
use Storable 'dclone';
use Scalar::Util 'blessed';
use String::Util 'trim';
use SNMP::Info;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  load_cache_for_device
  add_snmpinfo_aliases
  make_snmpwalk_browsable
  fixup_browser_from_aliases
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::Snapshot

=head1 DESCRIPTION

Helper functions for L<SNMP::Info> instances.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 load_cache_for_device( $device )

Tries to find a device cache in database or on disk, or build one from
a net-snmp snmpwalk on disk. Returns a cache.

=cut

sub load_cache_for_device {
  my $device = shift;
  return {} unless ($device->is_pseudo or not $device->in_storage);

  my $pseudo_cache = catfile( catdir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'logs', 'snapshots'), $device->ip );
  my $loadmibs = schema('netdisco')->resultset('SNMPObject')->count;

  if (-f $pseudo_cache and not $loadmibs) {
      warning "device snapshot exists ($pseudo_cache) but no MIB data available.";
      warning 'skipping offline cache load - run a "loadmibs" job if you want this!';
      return {};
  }

  my %oids = ();

  # ideally we have a cache in the db
  if ($device->is_pseudo
      and not $device->oids->search({ -or => [
        -bool => \q{ array_length(oid_parts, 1) IS NULL },
        -bool => \q{ jsonb_typeof(value) != 'array' }, ] })->count) {

      my @rows = $device->oids->search({},{
          join => 'oid_fields',
          columns => [qw/oid value/],
          select => [qw/oid_fields.mib oid_fields.leaf/], as => [qw/mib leaf/],
      })->hri->all;

      $oids{$_->{oid}} = {
          %{ $_ },
          value => (@{ from_json($_->{value}) })[0],
      } for @rows;
  }
  # or we have an snmpwalk file on disk
  elsif (-f $pseudo_cache and not $device->in_storage) {
      debug sprintf "importing snmpwalk from disk ($pseudo_cache)";

      my @lines = read_lines($pseudo_cache);
      my %store = ();

      # sometimes we're given a snapshot with iso. instead of .1.
      if ($lines[0] !~ m/^.\d/) {
          warning 'snapshot file rejected - has translated names/values instead of numeric';
          return {};
      }

      # parse the snmpwalk output which looks like
      # .1.0.8802.1.1.2.1.1.1.0 = INTEGER: 30
      foreach my $line (@lines) {
          my ($oid, $type, $value) = $line =~ m/^(\S+)\s+=\s+(?:([^:]+):\s+)?(.+)$/;
          next unless $oid and $value;

          # empty string makes the capture go wonky
          $value = '' if $value =~ m/^[^:]+: ?$/;

          # remove quotes from strings
          $value =~ s/^"//;
          $value =~ s/"$//;

          $store{$oid} = {
            oid       => $oid,
            oid_parts => [], # not needed temporarily 
            value     => to_json([ ((defined $type and $type eq 'BASE64') ? $value
                                                                          : encode_base64(trim($value), '')) ]),
          };
      }

      # put into the database (temporarily)
      # this MUST happen here and not be refactored into make_snmpwalk_browsable
      # because make_snmpwalk_browsable is also called from snapshot job.
      # it will all be cleaned up after
      schema('netdisco')->txn_do(sub {
        $device->oids->delete;
        $device->oids->populate([values %store]);
      });

      # get back out of the database as tables with related snmp_object (for the enum)
      %oids = make_snmpwalk_browsable($device);
      $oids{$_}->{value} = (@{ from_json( $oids{$_}->{value} ) })[0]
        for keys %oids;
  }

  # inflate the cache to an SNMP::Info cache instance
  return snmpwalk_to_snmpinfo_cache(%oids);
}

=head2 make_snmpwalk_browsable( $device )

Takes the device_browser rows for a device and rewrites them to convert
table rows to hashref, enum values translated, and oid_parts filled.

=cut

sub make_snmpwalk_browsable {
  my $device = shift;
  my %oids = ();

  # to get relation from device_browser to snmp_object working for tables
  # we need to temporarily populate device_browser with potential table oids.
  # it will all be cleaned up after
  my %value_oids = map {($_ => 1)} $device->oids->get_column('oid')->all;
  my %table_oids = ();

  foreach my $orig_oid (keys %value_oids) {
      (my $oid = $orig_oid) =~ s/\.\d+$//;
      my $new_oid = '';

      while (length($oid)) {
          $oid =~ s/^(\.\d+)//;
          $new_oid .= $1;
          $table_oids{$new_oid} = {oid => $new_oid, oid_parts => []}
            unless exists $value_oids{$new_oid};
      }
  }

  $device->oids->populate([values %table_oids]);
  my @rows = $device->oids->search({},{
      join => 'oid_fields',
      columns => [qw/oid value/],
      select => [qw/oid_fields.mib oid_fields.leaf oid_fields.enum/], as => [qw/mib leaf enum/],
  })->hri->all;

  $oids{$_->{oid}} = {
      %{ $_ },
      value => (defined $_->{value} ? decode_base64( (@{ from_json($_->{value}) })[0] ) : q{}),
  } for grep {$_->{leaf} or length( (@{ from_json($_->{value}) })[0] )}
             @rows;

  %oids = collapse_snmp_tables(%oids);
  %oids = resolve_enums(%oids);
  
  # walk leaves and table leaves to b64 encode again
  # build the oid_parts list
  foreach my $k (keys %oids) {
      my $value = (defined $oids{$k}->{value} ? $oids{$k}->{value} : q{});

      # always a JSON array of single element
      if (ref {} eq ref $value) {
          $oids{$k}->{value} = to_json([{ map {($_ => encode_base64(trim($value->{$_}), ''))} keys %{ $value } }]);
      }
      else {
          $oids{$k}->{value} = to_json([encode_base64(trim($value), '')]);
      }

      $oids{$k}->{oid_parts} = [ grep {length} (split m/\./, $oids{$k}->{oid}) ];
  }

  # store the device cache for real, now
  schema('netdisco')->txn_do(sub {
    $device->oids->delete;
    $device->oids->populate([map {
        { oid => $_->{oid}, oid_parts => $_->{oid_parts}, value => $_->{value} }
    } values %oids]);
    debug sprintf 'replaced %d browsable oids in db', scalar keys %oids;
  });

  return %oids;
}

=head2 collapse_snmp_tables ( %oids )

In an snmpwalk where table rows are individual entries, gather them
up into a hashref. Returns %oids hash similar to what's passed in.

=cut

sub collapse_snmp_tables {
  my %oids = @_;
  return () unless scalar keys %oids;

  OID: foreach my $orig_oid (sort {sortable_oid($a) cmp sortable_oid($b)} keys %oids) {
      my $oid = $orig_oid;
      my $idx = '';

      # walk down the oid until we hit a known leaf
      while (length($oid) and !defined $oids{$oid}->{leaf}) {
          $oid =~ s/\.(\d+)$//;
          $idx = (length $idx ? "${1}.${idx}" : $1);
      }

      if (0 == length($oid)) {
          # we never found a leaf, delete it and move on
          delete $oids{$orig_oid};
          next OID;
      }

      $idx ||= '.0';
      $idx =~ s/^\.//;

      if ($idx eq '0') {
          if ($oid eq $orig_oid and $oid =~ m/\.0$/) {
              # generally considered to be a bad idea, sometimes the OID
              # is standardised with .0 e.g. .1.3.6.1.2.1.1.3.0 sysUpTimeInstance
              # - do nothing as the value is already OK
          }
          else {
              $oids{$oid}->{value} = $oids{$orig_oid}->{value};
          }
      }
      else {
          # on rare occasions a vendor returns .0 and .something
          # this will overwrite the .0 (requires the sorting above)
          $oids{$oid}->{value} = {} if ref {} ne ref $oids{$oid}->{value};
          $oids{$oid}->{value}->{$idx} = $oids{$orig_oid}->{value};
      }

      delete $oids{$orig_oid} if $orig_oid ne $oid;
  }

  # remove temporary entries added to resolve table names
  delete $oids{$_}
    for grep {!defined $oids{$_}->{value}
              or (ref q{} eq ref $oids{$_}->{value} and $oids{$_}->{value} eq '')}
             keys %oids;

  return %oids;
}

=head2 resolve_enums ( %oids )

In an snmpwalk where the values are untranslated but enumerated types,
convert the values. Returns %oids hash similar to what's passed in.

=cut

sub resolve_enums {
  my %oids = @_;
  return () unless scalar keys %oids;

  foreach my $oid (keys %oids) {
      next unless $oids{$oid}->{enum};

      my $value = $oids{$oid}->{value};
      my %emap = map { reverse split m/\(/ }
                 map { s/\)//; $_ }
                     @{ $oids{$oid}->{enum} };

      if (ref q{} eq ref $value) {
          $oids{$oid}->{value} = $emap{$value} if exists $emap{$value};
      }
      elsif (ref {} eq ref $value) {
          foreach my $k (keys %$value) {
              $oids{$oid}->{value}->{$k} = $emap{ $value->{$k} }
                if exists $emap{ $value->{$k} };
          }
      }
  }

  return %oids;
}

=head2 snmpwalk_to_snmpinfo_cache( %oids )

Takes an snmpwalk with collapsed tables and returns an SNMP::Info
instance using that as the cache.

=cut

sub snmpwalk_to_snmpinfo_cache {
  my %walk = @_;
  return () unless scalar keys %walk;

  # unpack the values
  foreach my $oid (keys %walk) {
      my $value = $walk{$oid}->{value};

      if (ref q{} eq ref $value) {
          $walk{$oid}->{value} = decode_base64($walk{$oid}->{value});
      }
      elsif (ref {} eq ref $value) {
          foreach my $k (keys %$value) {
              $walk{$oid}->{value}->{$k}
                = decode_base64($walk{$oid}->{value}->{$k});
          }
      }
  }

  my $info = SNMP::Info->new({
    Offline => 1,
    Cache => {},
    Session => {},
    MibDirs => [ get_mibdirs() ],
    AutoSpecify => 0,
    IgnoreNetSNMPConf => 1,
    Debug => ($ENV{INFO_TRACE} || 0),
    DebugSNMP => ($ENV{SNMP_TRACE} || 0),
  });

  foreach my $oid (keys %walk) {
      my $qleaf = $walk{$oid}->{mib} . '::' . $walk{$oid}->{leaf};
      (my $snmpqleaf = $qleaf) =~ s/[-:]/_/g;

      $info->_cache($walk{$oid}->{leaf}, $walk{$oid}->{value});
      $info->_cache($snmpqleaf, $walk{$oid}->{value});
  }

  # debug sprintf "snmpwalk_to_snmpinfo: cache size: %d", scalar keys %{ $info->cache };
  return add_snmpinfo_aliases($info);
}

=head2 add_snmpinfo_aliases( $snmp_info_instance | $snmp_info_cache )

Add in any GLOBALS and FUNCS aliases from the SNMP::Info device class
or else a set of defaults that allow device discovery. Returns the cache.

=cut

sub add_snmpinfo_aliases {
  my $info = shift or return {};

  if (not blessed $info) {
      $info = SNMP::Info->new({
        Offline => 1,
        Cache => $info,
        Session => {},
        MibDirs => [ get_mibdirs() ],
        AutoSpecify => 0,
        IgnoreNetSNMPConf => 1,
        Debug => ($ENV{INFO_TRACE} || 0),
        DebugSNMP => ($ENV{SNMP_TRACE} || 0),
      });
  }

  my %globals = %{ $info->globals };
  my %funcs   = %{ $info->funcs };

  while (my ($alias, $leaf) = each %globals) {
      next if $leaf =~ m/\.\d+$/;
      $info->_cache($alias, $info->$leaf) if $info->$leaf;
  }

  while (my ($alias, $leaf) = each %funcs) {
      $info->_cache($alias, dclone $info->$leaf) if ref q{} ne ref $info->$leaf;
  }

  # SNMP::Info::Layer3 has some weird structures we can try to fix here

  my %propfix = (
    chassisId     => 'serial1',
    ospfRouterId  => 'router_ip',
    bgpIdentifier => 'bgp_id',
    bgpLocalAs    => 'bgp_local_as',
    ifPhysAddress => 'mac',
    qw(
      model  model
      serial serial
      os_ver os_ver
      os     os
    ),
  );

  foreach my $prop (keys %propfix) {
      my $val = $info->$prop;
      $val = [values %$val]->[0] if ref $val eq 'HASH';
      $info->_cache($propfix{$prop}, $val);
  }

  # netdisco will try uptime or hrSystemUptime or sysUptime (but not sysUptimeInstance)
  if (defined $info->sysUpTimeInstance) {
      my $uptime = (ref {} eq ref $info->sysUpTimeInstance)
        ? ($info->sysUpTimeInstance->{0} || $info->sysUpTimeInstance->{''})
        : $info->sysUpTimeInstance;
      
      if (!defined $info->uptime) {
          $info->_cache('uptime', $uptime);
      }
      if (!defined $info->sysUpTime) {
          $info->_cache('sysUpTime', $uptime);
      }
  }

  # now for any other SNMP::Info method in GLOBALS or FUNCS which Netdisco
  # might call, but will not have data, we fake a cache entry to avoid
  # throwing errors

  while (my $method = <DATA>) {
    $method =~ s/\s//g;
    next unless length $method and not $info->$method;

    $info->_cache($method, '') if exists $globals{$method};
    $info->_cache($method, {}) if exists $funcs{$method};
  }

  # debug sprintf "add_snmpinfo_aliases: cache size: %d", scalar keys %{ $info->cache };
  return $info->cache;
}

=head2 fixup_browser_from_aliases( $device_instance, $snmp_info_instance )

Now we have a solid SNMP::Info cache, if there are any fixups of browser
data they can happen here.

=cut

sub fixup_browser_from_aliases {
  my $device = shift or return;
  my $info = shift or return;

  my $e_type = $info->e_type;
  if (scalar keys %$e_type) {
      my $row = $device->oids->find({ oid => '.1.3.6.1.2.1.47.1.1.1.1.3' });
      $row->update({ value =>
        to_json([{ map {($_ => encode_base64(trim($e_type->{$_}), ''))} keys %{ $e_type } }]) });
  }
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
