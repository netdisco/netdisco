package App::Netdisco::Util::SNMP;

use Dancer qw/:syntax :script !to_json !from_json/;
use App::Netdisco::Util::DeviceAuth 'get_external_credentials';

use MIME::Base64 'decode_base64';
use Storable 'thaw';
use JSON::PP;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  get_communities
  snmp_comm_reindex
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

true;
