package App::Netdisco::Util::VRF;

use strict;
use warnings;

use Dancer qw/:syntax :script !pass/;
use App::Netdisco::Util::Permission 'acl_matches';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  vrf_collection_enabled
  vrf_skipped
  netdisco_vrf
  vrf_instances_for
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::VRF

=head1 DESCRIPTION

Helper subroutines for collecting VRF data from devices.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 vrf_collection_enabled( $device )

True only when the C<store_vrfs> setting is on and the device does not match
C<skip_vrf_devices>.

=cut

sub vrf_collection_enabled {
  my $device = shift;
  return (setting('store_vrfs') and not acl_matches($device, 'skip_vrf_devices'));
}

=head2 vrf_skipped( $device, $local_name )

True when the VRF name, exactly as the device reports it, is listed in
C<vrf_no_name>, or C<< <device ip>:<name> >> is listed in C<vrf_no_devicevrf>.
Never true for the default table, whichever of C<default> or the empty string
names it.

=cut

sub vrf_skipped {
  my ($device, $name) = @_;
  return 0 if not defined $name or $name eq '' or $name eq 'default';

  my $no_name = setting('vrf_no_name');
  return 1 if ref [] eq ref $no_name and scalar grep { $_ eq $name } @$no_name;

  my $no_devicevrf = setting('vrf_no_devicevrf');
  my $ip = $device->ip;
  return 1 if ref [] eq ref $no_devicevrf
    and scalar grep { $_ eq "$ip:$name" } @$no_devicevrf;

  return 0;
}

=head2 netdisco_vrf( $snmpinfo_name )

SNMP::Info names the global routing table C<default>; Netdisco stores it as
the empty string. Returns that, or the name unchanged for any other VRF.

=cut

sub netdisco_vrf {
  my $name = shift;
  return (defined $name and $name eq 'default') ? '' : $name;
}

=head2 vrf_instances_for( $device, $snmp )

Returns the hashref from C<< $snmp->vrf_instances >> without the VRFs skipped
by L</vrf_skipped>, or C<undef> when collection is disabled for the device or
the SNMP::Info class has no VRF support (C<vrf_instances_complete> is
C<undef>). No SNMP method is called when collection is disabled.

The instances are read here, in the default context, because C<update()>
clears SNMP::Info's cache.

=cut

sub vrf_instances_for {
  my ($device, $snmp) = @_;
  return undef unless vrf_collection_enabled($device);
  return undef unless defined $snmp->vrf_instances_complete;

  my $instances = $snmp->vrf_instances || {};
  return { map { ($_ => $instances->{$_}) }
           grep { not vrf_skipped($device, $_) } keys %$instances };
}

=head1 SEE ALSO

L<SNMP::Info::VRF>

=cut

1;
