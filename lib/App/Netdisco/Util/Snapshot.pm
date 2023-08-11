package App::Netdisco::Util::Snapshot;

use Dancer qw/:syntax :script !to_json !from_json/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::SNMP 'sortable_oid';

use File::Spec::Functions qw/splitdir catdir catfile/;
use MIME::Base64 qw/encode_base64 decode_base64/;
use File::Slurper qw/read_lines read_text/;
use Sub::Util 'subname';
use Storable qw/dclone nfreeze thaw/;
use Scalar::Util 'blessed';
use Module::Load ();
use SNMP::Info;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  load_cache_for_device
  snmpwalk_to_cache

  gather_every_mib_object
  dump_cache_to_browserdata
  add_snmpinfo_aliases

  get_oidmap_from_database
  get_oidmap_from_mibs_files
  get_mibs_for
  get_munges
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

  # ideally we have a cache in the db
  if ($device->is_pseudo and my $snapshot = $device->snapshot) {
      return thaw( decode_base64( $snapshot->cache ) );
  }

  # or we have a file on disk - could be cache or walk
  my $pseudo_cache = catfile( catdir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'logs', 'snapshots'), $device->ip );
  if (-f $pseudo_cache and not $device->in_storage) {
      my $content = read_text($pseudo_cache);

      if ($content =~ m/^\.1/) {
          my %oids = ();

          # parse the snmpwalk output which looks like
          # .1.0.8802.1.1.2.1.1.1.0 = INTEGER: 30
          my @lines = split /\n/, $content;
          foreach my $line (@lines) {
              my ($oid, $val) = $line =~ m/^(\S+) = (?:[^:]+: )?(.+)$/;
              next unless $oid and $val;

              # empty string makes the capture go wonky
              $val = '' if $val =~ m/^[^:]+: ?$/;

              # remove quotes from strings
              $val =~ s/^"//;
              $val =~ s/"$//;

              $oids{$oid} = $val;
          }

          return snmpwalk_to_cache(%oids);
      }
      else {
          my $cache = thaw( decode_base64( $content ) );
          return add_snmpinfo_aliases( $cache );
      }

      # there is a late phase discover worker to generate the oids
      # and also to save the cache into the database, because we want
      # to wait for device-specific SNMP::Info class and all its methods.
  }

  return {};
}

=head2 snmpwalk_to_cache ( %oids )

Take the snmpwalk of the device which is numeric (no MIB translateObj),
resolve to MIB identifiers using netdisco-mibs data, then return as an
SNMP::Info instance cache.

=cut

sub snmpwalk_to_cache {
  my %oids = @_;
  return () unless scalar keys %oids;

  my %oidmap = reverse get_oidmap_from_database();
  my %leaves = ();

  OID: foreach my $orig_oid (keys %oids) {
      my $oid = $orig_oid;
      my $idx = '';

      while (length($oid) and !exists $oidmap{$oid}) {
          $oid =~ s/\.(\d+)$//;
          $idx = ((defined $idx and length $idx) ? "${1}.${idx}" : $1);
      }

      if (exists $oidmap{$oid}) {
          $idx =~ s/^\.//;
          my $qleaf = $oidmap{$oid};
          my $key = $oid .'~~'. $qleaf;

          if ($idx eq 0) {
              $leaves{$key} = $oids{$orig_oid};
          }
          else {
              # on rare occasions a vendor returns .0 and .something
              delete $leaves{$key}
                if defined $leaves{$key} and ref q{} eq $leaves{$key};
              $leaves{$key}->{$idx} = $oids{$orig_oid};
          }

          # debug "snapshot $device - cached $oidmap{$oid}($idx) from $orig_oid";
          next OID;
      }

      # this is not too surprising
      # debug sprintf "cache builder - error:  missing OID %s in netdisco-mibs", $orig_oid;
  }

  my $info = SNMP::Info->new({
    Offline => 1,
    Cache => {},
    AutoSpecify => 0,
    Session => {},
  });

  foreach my $attr (keys %leaves) {
      my ($oid, $qleaf) = split m/~~/, $attr;
      my $val = $leaves{$attr};

      # resolve the enums if needed
      my $row = schema('netdisco')->resultset('SNMPObject')->find($oid);
      if ($row and $row->enum) {
          my %emap = map { reverse split m/\(/ }
                     map { s/\)//; $_ }
                     @{ $row->enum };

          if (ref q{} eq ref $val) {
              $val = $emap{$val} if exists $emap{$val};
          }
          elsif (ref {} eq ref $val) {
              foreach my $k (keys %$val) {
                  $val->{$k} = $emap{ $val->{$k} }
                    if exists $emap{ $val->{$k} };
              }
          }
      }

      my $leaf = $qleaf;
      $leaf =~ s/.+:://;

      my $snmpqleaf = $qleaf;
      $snmpqleaf =~ s/[-:]/_/g;

      # do we need this ?? $info->_cache($oid,  $leaves{$attr});
      $info->_cache($leaf, $leaves{$attr});
      $info->_cache($snmpqleaf, $leaves{$attr});
  }

  debug sprintf "snmpwalk_to_cache: cache size: %d", scalar keys %{ $info->cache };

  # inject a basic set of SNMP::Info globals and funcs aliases
  # which are needed for initial device discovery
  add_snmpinfo_aliases($info);

  return $info->cache;
}

=head2 gather_every_mib_object( $device, $snmp, @extramibs? )

Gathers evey MIB Object in the MIBs loaded for the device and store
to the database for SNMP browser.

Optionally add a list of vendors, MIBs, or SNMP:Info class for extra MIB
Objects from the netdisco-mibs bundle.

The passed SNMP::Info instance has its cache update with the data.

=cut

sub gather_every_mib_object {
  my ($device, $snmp, @extra) = @_;

  # get MIBs loaded for device
  my @mibs = keys %{ $snmp->mibs() };
  my @extra_mibs = get_mibs_for(@extra);
  debug sprintf "covering %d MIBs", (scalar @mibs + scalar @extra_mibs);
  SNMP::loadModules($_) for @extra_mibs;

  # get qualified leafs for those MIBs from snmp_object
  my %oidmap = get_oidmap_from_database(@mibs, @extra_mibs);
  debug sprintf "gathering %d MIB Objects", scalar keys %oidmap;

  foreach my $qleaf (sort {sortable_oid($oidmap{$a}) cmp sortable_oid($oidmap{$b})} keys %oidmap) {
      my $leaf = $qleaf;
      $leaf =~ s/.+:://;

      my $snmpqleaf = $qleaf;
      $snmpqleaf =~ s/[-:]/_/g;

      # gather the leaf
      $snmp->$snmpqleaf;

      # skip any leaf which did not return data from device
      # this works for both funcs and globals as funcs create stub global
      next unless exists $snmp->cache->{'_'. $snmpqleaf};

      # store a short name alias which is needed for netdisco actions
      $snmp->_cache($leaf, $snmp->$snmpqleaf);
  }
}

=head2 dump_cache_to_browserdata( $device, $snmp )

Dumps any valid MIB leaf from the passed SNMP::Info instance's cache into
the Netdisco database SNMP Browser table.

Ideally the leafs are fully qualified, but if not then a best effort will
be made to find their correct MIB.

=cut

sub dump_cache_to_browserdata {
  my ($device, $snmp) = @_;

  my %qoidmap = get_oidmap_from_database();
  my %oidmap  = get_leaf_to_qleaf_map();
  my %munges  = get_munges($snmp);

  my $cache = $snmp->cache;
  my %oids = ();

  foreach my $key (keys %$cache) {
      next unless $key and $key =~ m/^_/;

      my $snmpqleaf = $key;
      $snmpqleaf =~ s/^_//;

      my $qleaf = $snmpqleaf;
      $qleaf =~ s/__/::/;
      $qleaf =~ s/_/-/g;

      my $leaf = $qleaf;
      $leaf =~ s/.+:://;

      next unless exists $qoidmap{$qleaf}
                  or (exists $oidmap{$leaf} and exists $qoidmap{ $oidmap{$leaf} });

      my $oid  = exists $qoidmap{$qleaf} ? $qoidmap{$qleaf} : $qoidmap{ $oidmap{$leaf} };
      my $data = exists $cache->{'store'}{$snmpqleaf} ? $cache->{'store'}{$snmpqleaf}
                                                      : $cache->{$key};
      next unless defined $data;

      push @{ $oids{$oid} }, {
        oid => $oid,
        oid_parts => [ grep {length} (split m/\./, $oid) ],
        leaf  => $leaf,
        qleaf => $qleaf,
        munge => ($munges{$snmpqleaf} || $munges{$leaf}),
        value => encode_base64( nfreeze( [$data] ) ),
      };
  }

  %oids = map { ($_ => [sort {length($b->{qleaf}) <=> length($a->{qleaf})} @{ $oids{$_} }]) }
          keys %oids;

  schema('netdisco')->txn_do(sub {
    my $gone = $device->oids->delete;
    debug sprintf 'removed %d oids from db', $gone;
    $device->oids->populate([ sort {sortable_oid($a->{oid}) cmp sortable_oid($b->{oid})}
                              map  { delete $_->{qleaf}; $_ }
                              map  { $oids{$_}->[0] } keys %oids ]);
    debug sprintf 'added %d new oids to db', scalar keys %oids;
  });
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
        AutoSpecify => 0,
        Session => {},
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

  # SNMP::Info::Layer3 has some weird aliases we can fix here
  $info->_cache('serial1',      $info->chassisId->{''})         if ref {} eq ref $info->chassisId;
  $info->_cache('router_ip',    $info->ospfRouterId->{''})      if ref {} eq ref $info->ospfRouterId;
  $info->_cache('bgp_id',       $info->bgpIdentifier->{''})     if ref {} eq ref $info->bgpIdentifier;
  $info->_cache('bgp_local_as', $info->bgpLocalAs->{''})        if ref {} eq ref $info->bgpLocalAs;
  $info->_cache('sysUpTime',    $info->sysUpTimeInstance->{''}) if ref {} eq ref $info->sysUpTimeInstance
                                                                   and not $info->sysUpTime;
  $info->_cache('mac',          $info->ifPhysAddress->{1})      if ref {} eq ref $info->ifPhysAddress;

  # now for any other SNMP::Info method in GLOBALS or FUNCS which Netdisco
  # might call, but will not have data, we fake a cache entry to avoid
  # throwing errors

  while (my $method = <DATA>) {
    $method =~ s/\s//g;
    next unless length $method and not $info->$method;

    $info->_cache($method, '') if exists $globals{$method};
    $info->_cache($method, {}) if exists $funcs{$method};
  }

  debug sprintf "add_snmpinfo_aliases: cache size: %d", scalar keys %{ $info->cache };
  return $info->cache;
}

=head2 get_leaf_to_qleaf_map( )

=cut

sub get_leaf_to_qleaf_map {
  debug "loading database leaf to qleaf map";

  my %oidmap = map { ( $_->{leaf} => (join '::', $_->{mib}, $_->{leaf}) ) }
               schema('netdisco')->resultset('SNMPObject')
                                 ->search({
                                     num_children => 0,
                                     leaf => { '!~' => 'anonymous#\d+$' },
                                     -or => [
                                       type   => { '<>' => '' },
                                       access => { '~' => '^(read|write)' },
                                       \'oid_parts[array_length(oid_parts,1)] = 0'
                                     ],
                                   },{columns => [qw/mib leaf/], order_by => 'oid_parts'})
                                 ->hri->all;

  debug sprintf "loaded %d mapped objects", scalar keys %oidmap;
  return %oidmap;
}

=head2 get_oidmap_from_database( @mibs? )

=cut

sub get_oidmap_from_database {
  my @mibs = @_;
  debug "loading netdisco-mibs object cache (database)";

  my %oidmap = map { ((join '::', $_->{mib}, $_->{leaf}) => $_->{oid}) }
               schema('netdisco')->resultset('SNMPObject')
                                 ->search({
                                     (scalar @mibs ? (mib => { -in => \@mibs }) : ()),
                                     num_children => 0,
                                     leaf => { '!~' => 'anonymous#\d+$' },
                                     -or => [
                                       type   => { '<>' => '' },
                                       access => { '~' => '^(read|write)' },
                                       \'oid_parts[array_length(oid_parts,1)] = 0'
                                     ],
                                   },{columns => [qw/mib oid leaf/], order_by => 'oid_parts'})
                                 ->hri->all;

  if (not scalar @mibs) {
      debug sprintf "loaded %d MIB objects", scalar keys %oidmap;
  }

  return %oidmap;
}

=head2 get_oidmap_from_mibs_files( @vendors? )

Read in netdisco-mibs translation report and make an OID -> leafname map this
is an older version of get_oidmap which uses disk file test on my laptop shows
this version is four seconds and the database takes two.

=cut

sub get_oidmap_from_mibs_files {
  debug "loading netdisco-mibs object cache (netdisco-mibs)";

  my $home = (setting('mibhome') || catdir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'netdisco-mibs'));
  my $reports = catdir( $home, 'EXTRAS', 'reports' );
  my @maps = map  { (splitdir($_))[-1] }
             grep { ! m/^(?:EXTRAS)$/ }
             grep { ! m/\./ }
             grep { -f }
             glob (catfile( $reports, '*_oids' ));

  my @report = ();
  push @report, read_lines( catfile( $reports, $_ ), 'latin-1' )
    for (qw(rfc_oids net-snmp_oids cisco_oids), @maps);

  my %oidmap = ();
  foreach my $line (@report) {
    my ($oid, $qual_leaf, $rest) = split m/,/, $line;
    next unless defined $oid and defined $qual_leaf;
    next if exists $oidmap{$oid};
    my ($mib, $leaf) = split m/::/, $qual_leaf;
    $oidmap{$oid} = $leaf;
  }

  debug sprintf "loaded %d MIB objects",
    scalar keys %oidmap;
  return %oidmap;
}

=head2 get_mibs_for( @extra )

=cut

sub get_mibs_for {
  my @extra = @_;
  my @mibs = ();

  my $home = (setting('mibhome') || catdir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'netdisco-mibs'));
  my $cachedir = catdir( $home, 'EXTRAS', 'indexes', 'cache' );

  foreach my $item (@extra) {
      next unless $item;
      if ($item =~ m/^[a-z0-9-]+$/) {
          push @mibs, map { (split m/\s+/)[0] }
                      read_lines( catfile( $cachedir, $item ), 'latin-1' );
      }
      elsif ($item =~ m/::/) {
          Module::Load::load $item;
          $item .= '::MIBS';
          {
            no strict 'refs';
            push @mibs, keys %${item};
          }
      }
      else {
          push @mibs, $item;
      }
  }

  return @mibs;
}

=head2 get_munges( $snmpinfo )

=cut

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
