package App::Netdisco::Util::SNMP;

use Dancer qw/:syntax :script !to_json !from_json/;
use App::Netdisco::Util::DeviceAuth 'get_external_credentials';
use Dancer::Plugin::DBIC 'schema';

use File::Spec::Functions qw/splitdir catdir catfile/;
use MIME::Base64 qw/encode_base64 decode_base64/;
use File::Slurper qw/read_lines read_text/;
use File::Path 'make_path';
use Sub::Util 'subname';
use Storable qw/dclone nfreeze thaw/;
use JSON::PP;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  get_communities
  snmp_comm_reindex
  convert_oids_to_cache
  get_cache_for_device
  get_oidmap
  get_munges
  sortable_oid
  decode_and_munge
  %ALL_MUNGERS
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::SNMP

=head1 DESCRIPTION

Helper functions for L<SNMP::Info> instances.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 sortable_oid( $oid, $seglen? )

Take an OID and return a version of it which is sortable using C<cmp>
operator. Works by zero-padding the numeric parts all to be length
C<< $seglen >>, which defaults to 6.

=cut

# take oid and make comparable
sub sortable_oid {
  my ($oid, $seglen) = @_;
  $seglen ||= 6;
  return $oid if $oid !~ m/^[0-9.]+$/;
  $oid =~ s/^(\.)//; my $leading = $1;
  $oid = join '.', map { sprintf("\%0${seglen}d", $_) } (split m/\./, $oid);
  return (($leading || '') . $oid);
}

=head2 get_communities( $device, $mode )

Takes the current C<device_auth> setting and pushes onto the front of the list
the last known good SNMP settings used for this mode (C<read> or C<write>).

=cut

sub get_communities {
  my ($device, $mode) = @_;
  $mode ||= 'read';

  my $seen_tags = {}; # for cleaning community table
  my $config = (setting('device_auth') || []);
  my @communities = ();

  # first of all, use external command if configured
  push @communities, get_external_credentials($device, $mode);

  # last known-good by tag
  my $tag_name = 'snmp_auth_tag_'. $mode;
  my $stored_tag = eval { $device->community->$tag_name };

  if ($device->in_storage and $stored_tag) {
    foreach my $stanza (@$config) {
      if ($stanza->{tag} and $stored_tag eq $stanza->{tag}) {
        push @communities, {%$stanza, only => [$device->ip]};
        last;
      }
    }
  }

  # try last-known-good v2 read
  push @communities, {
    read => 1, write => 0, driver => 'snmp',
    only => [$device->ip],
    community => $device->snmp_comm,
  } if defined $device->snmp_comm and $mode eq 'read';

  # try last-known-good v2 write
  my $snmp_comm_rw = eval { $device->community->snmp_comm_rw };
  push @communities, {
    write => 1, read => 0, driver => 'snmp',
    only => [$device->ip],
    community => $snmp_comm_rw,
  } if $snmp_comm_rw and $mode eq 'write';

  # clean the community table of obsolete tags
  eval { $device->community->update({$tag_name => undef}) }
    if $device->in_storage
       and (not $stored_tag or !exists $seen_tags->{ $stored_tag });

  return ( @communities, @$config );
}

=head2 convert_oids_to_cache ( %oids )

=cut

sub convert_oids_to_cache {
  my %oids = @_;
  return () unless scalar keys %oids;

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

=head2 get_cache_for_device( $device )

=cut

sub get_cache_for_device {
  my $device = shift;
  return {} unless ($device->is_pseudo or not $device->in_storage);

  # ideally we have a cache in the db
  if ($device->is_pseudo and my $snapshot = $device->snapshot) {
      my $cache = thaw( decode_base64( $snapshot->cache ) );
      return $cache;
  }

  # or we have a file on disk - could be cache or rows
  # so we make both the rows in oids and the cache
  my $pseudo_cache = catfile( catdir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'logs', 'snapshots'), $device->ip );
  if (-f $pseudo_cache and not $device->in_storage) {
      my $content = read_text($pseudo_cache);

      if ($content =~ m/^\.1/) {
          my %oids = ();

          # parse the snmpwalk output which looks like
          # .1.0.8802.1.1.2.1.1.1.0 = INTEGER: 30
          my @lines = split /\n/, $content;
          foreach my $line (@lines) {
              my ($oid, $val) = $line =~ m/^(\S+) = \w+: (.+)$/;
              next unless $oid and $val;

              # resolve enum values in oids
              my $row = schema('netdisco')->find($oid) or next;
              my %emap = map { split m/\(/ }
                         map { s/\)//; $_ }
                         @{ $row->enum };

              if (scalar keys %emap and exists $emap{$val}) {
                  $val = $emap{$val};
              }

              $oids{$oid} = $val;
          }

          my $cache = convert_oids_to_cache(%oids);

          my $frozen = encode_base64( nfreeze( $cache ) );
          $device->update_or_create_related('snapshot', { cache => $frozen });

          return $cache;
      }
      else {
          $device->update_or_create_related('snapshot', { cache => $content });
          my $cache = thaw( decode_base64( $content ) );
          return $cache;
      }

      # device now has a cache but no oids,
      # there is a late phase discover worker to generate the oids
      # because that needs the device-specific SNMP::Info class
  }

  return {};
}

=head2 snmp_comm_reindex( $snmp, $device, $vlan )

Takes an established L<SNMP::Info> instance and makes a fresh connection using
community indexing, with the given C<$vlan> ID. Works for all SNMP versions.

Inherits the C<vtp_version> from the previous L<SNMP::Info> instance.

Passing VLAN "C<0>" (zero) will reset the indexing to the basic v2 community
or v3 empty context.

=cut

sub snmp_comm_reindex {
  my ($snmp, $device, $vlan) = @_;
  my $ver = $snmp->snmp_ver;
  my $vtp = $snmp->vtp_version;

  if ($ver == 3) {
      my $prefix = '';
      my @comms = get_communities($device, 'read');
      # find a context prefix configured by the user
      foreach my $c (@comms) {
          next unless $c->{tag}
            and $c->{tag} eq (eval { $device->community->snmp_auth_tag_read } || '');
          $prefix = $c->{context_prefix} and last;
      }
      $prefix ||= 'vlan-';

      if ($vlan =~ /^[0-9]+$/i && $vlan) {
        debug sprintf '[%s] reindexing to "%s%s" (ver: %s, class: %s)',
        $device->ip, $prefix, $vlan, $ver, $snmp->class;
        $snmp->update(Context => ($prefix . $vlan));
      } elsif ($vlan =~ /^[a-z0-9]+$/i && $vlan) {
        debug sprintf '[%s] reindexing to "%s" (ver: %s, class: %s)',
          $device->ip, $vlan, $ver, $snmp->class;
        $snmp->update(Context => ($vlan));
      } else {
        debug sprintf '[%s] reindexing without context (ver: %s, class: %s)',
          $device->ip, $ver, $snmp->class;
        $snmp->update(Context => '');
      }
  }
  else {
      my $comm = $snmp->snmp_comm;

      debug sprintf '[%s] reindexing to vlan %s (ver: %s, class: %s)',
        $device->ip, $vlan, $ver, $snmp->class;
      $vlan ? $snmp->update(Community => $comm . '@' . $vlan)
            : $snmp->update(Community => $comm);
  }

  $snmp->cache({ _vtp_version => $vtp });
  return $snmp;
}

our %ALL_MUNGERS = (
    'SNMP::Info::munge_speed' => \&SNMP::Info::munge_speed,
    'SNMP::Info::munge_highspeed' => \&SNMP::Info::munge_highspeed,
    'SNMP::Info::munge_ip' => \&SNMP::Info::munge_ip,
    'SNMP::Info::munge_mac' => \&SNMP::Info::munge_mac,
    'SNMP::Info::munge_prio_mac' => \&SNMP::Info::munge_prio_mac,
    'SNMP::Info::munge_prio_port' => \&SNMP::Info::munge_prio_port,
    'SNMP::Info::munge_octet2hex' => \&SNMP::Info::munge_octet2hex,
    'SNMP::Info::munge_dec2bin' => \&SNMP::Info::munge_dec2bin,
    'SNMP::Info::munge_bits' => \&SNMP::Info::munge_bits,
    'SNMP::Info::munge_counter64' => \&SNMP::Info::munge_counter64,
    'SNMP::Info::munge_i_up' => \&SNMP::Info::munge_i_up,
    'SNMP::Info::munge_port_list' => \&SNMP::Info::munge_port_list,
    'SNMP::Info::munge_null' => \&SNMP::Info::munge_null,
    'SNMP::Info::munge_e_type' => \&SNMP::Info::munge_e_type,
    'SNMP::Info::Airespace::munge_64bits' => \&SNMP::Info::Airespace::munge_64bits,
    'SNMP::Info::CDP::munge_power' => \&SNMP::Info::CDP::munge_power,
    'SNMP::Info::CiscoAgg::munge_port_ifindex' => \&SNMP::Info::CiscoAgg::munge_port_ifindex,
    'SNMP::Info::CiscoPortSecurity::munge_pae_capabilities' => \&SNMP::Info::CiscoPortSecurity::munge_pae_capabilities,
    'SNMP::Info::CiscoStack::munge_port_status' => \&SNMP::Info::CiscoStack::munge_port_status,
    'SNMP::Info::EtherLike::munge_el_duplex' => \&SNMP::Info::EtherLike::munge_el_duplex,
    'SNMP::Info::IPv6::munge_physaddr' => \&SNMP::Info::IPv6::munge_physaddr,
    'SNMP::Info::Layer2::Airespace::munge_cd11n_ch_bw' => \&SNMP::Info::Layer2::Airespace::munge_cd11n_ch_bw,
    'SNMP::Info::Layer2::Airespace::munge_cd11_proto' => \&SNMP::Info::Layer2::Airespace::munge_cd11_proto,
    'SNMP::Info::Layer2::Airespace::munge_cd11_rateset' => \&SNMP::Info::Layer2::Airespace::munge_cd11_rateset,
    'SNMP::Info::Layer2::Aironet::munge_cd11_txrate' => \&SNMP::Info::Layer2::Aironet::munge_cd11_txrate,
    'SNMP::Info::Layer2::HP::munge_hp_c_id' => \&SNMP::Info::Layer2::HP::munge_hp_c_id,
    'SNMP::Info::Layer2::Nexans::munge_i_duplex' => \&SNMP::Info::Layer2::Nexans::munge_i_duplex,
    'SNMP::Info::Layer2::Nexans::munge_i_duplex_admin' => \&SNMP::Info::Layer2::Nexans::munge_i_duplex_admin,
    'SNMP::Info::Layer3::Altiga::munge_alarm' => \&SNMP::Info::Layer3::Altiga::munge_alarm,
    'SNMP::Info::Layer3::Aruba::munge_aruba_fqln' => \&SNMP::Info::Layer3::Aruba::munge_aruba_fqln,
    'SNMP::Info::Layer3::BayRS::munge_hw_rev' => \&SNMP::Info::Layer3::BayRS::munge_hw_rev,
    'SNMP::Info::Layer3::BayRS::munge_wf_serial' => \&SNMP::Info::Layer3::BayRS::munge_wf_serial,
    'SNMP::Info::Layer3::Extreme::munge_true_ok' => \&SNMP::Info::Layer3::Extreme::munge_true_ok,
    'SNMP::Info::Layer3::Extreme::munge_power_stat' => \&SNMP::Info::Layer3::Extreme::munge_power_stat,
    'SNMP::Info::Layer3::Huawei::munge_hw_peth_admin' => \&SNMP::Info::Layer3::Huawei::munge_hw_peth_admin,
    'SNMP::Info::Layer3::Huawei::munge_hw_peth_power' => \&SNMP::Info::Layer3::Huawei::munge_hw_peth_power,
    'SNMP::Info::Layer3::Huawei::munge_hw_peth_class' => \&SNMP::Info::Layer3::Huawei::munge_hw_peth_class,
    'SNMP::Info::Layer3::Huawei::munge_hw_peth_status' => \&SNMP::Info::Layer3::Huawei::munge_hw_peth_status,
    'SNMP::Info::Layer3::Timetra::munge_tmnx_state' => \&SNMP::Info::Layer3::Timetra::munge_tmnx_state,
    'SNMP::Info::Layer3::Timetra::munge_tmnx_e_class' => \&SNMP::Info::Layer3::Timetra::munge_tmnx_e_class,
    'SNMP::Info::Layer3::Timetra::munge_tmnx_e_swver' => \&SNMP::Info::Layer3::Timetra::munge_tmnx_e_swver,
    'SNMP::Info::MAU::munge_int2bin' => \&SNMP::Info::MAU::munge_int2bin,
    'SNMP::Info::NortelStack::munge_ns_grp_type' => \&SNMP::Info::NortelStack::munge_ns_grp_type,
);

=head2 decode_and_munge( $method, $data )

Takes some data from L<SNMP::Info> cache that has been Base64 encoded
and frozen with Storable, decodes it and then munge to handle data format,
before finally pretty render in JSON format.

=cut

sub get_code_info { return ($_[0]) =~ m/^(.+)::(.*?)$/ }
sub sub_name      { return (get_code_info $_[0])[1] }
sub class_name    { return (get_code_info $_[0])[0] }

sub decode_and_munge {
    my ($munger, $encoded) = @_;
    return undef unless defined $encoded and length $encoded;

    my $coder = JSON::PP->new->utf8->pretty->allow_nonref->allow_unknown->canonical;
    $coder->sort_by( sub { sortable_oid($JSON::PP::a) cmp sortable_oid($JSON::PP::b) } );

    my $data = (@{ thaw( decode_base64( $encoded ) ) })[0];
    return $coder->encode( $data )
      unless $munger and exists $ALL_MUNGERS{$munger};

    my $sub   = sub_name($munger);
    my $class = class_name($munger);
    Module::Load::load $class;

    if (ref {} eq ref $data) {
        my %munged;
        foreach my $key ( keys %$data ) {
            my $value = $data->{$key};
            next unless defined $value;
            $munged{$key} = $ALL_MUNGERS{$munger}->($value);
        }
        return $coder->encode( \%munged );
    }
    else {
        return unless $data;
        return $coder->encode( $ALL_MUNGERS{$munger}->($data) );
    }

}

# read in netdisco-mibs translation report and make an OID -> leafname map
sub get_oidmap {
  debug "-> loading netdisco-mibs object cache";

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

  debug sprintf "-> loaded %d objects from netdisco-mibs",
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
