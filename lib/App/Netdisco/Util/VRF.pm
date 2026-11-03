package App::Netdisco::Util::VRF;

use strict;
use warnings;

use Dancer qw/:syntax :script !pass/;
use App::Netdisco::Util::Permission 'acl_matches';
use App::Netdisco::Util::SNMP qw/snmp_vrf_context walk_mark incomplete_walks_for/;
use Scope::Guard 'guard';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  vrf_collection_enabled
  vrf_skipped
  netdisco_vrf
  vrf_instances_for
  each_vrf_instance
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

=head2 each_vrf_instance( $device, $snmp, $instances, \&reader, %options )

Reads every instance of C<$instances> (as from L</vrf_instances_for>) with
C<< $reader->($name, $instance, $switched) >>, which returns whatever the
caller needs from that instance.

C<default> is read first, then the attribution-mode instances (a first
context of kind C<none>, or no C<contexts> at all) sorted by name, all in
place with no C<update()>. Then each context-mode instance, sorted by name, in
its own context; the session is returned to the default context once, after
the last of them. An instance whose context this session cannot enter is not
read and is reported incomplete. So is one whose C<contexts> is empty, which
SNMP::Info gives for a context-mode VRF that no context serves; it costs no
SNMP call.

A read is complete only when C<< $snmp->vrf_read_complete($name) >> is 1 and
no walk since the read began came back short (C<incomplete_walks_for>, with
the C<walk_methods> option naming any further methods to check).

Returns a hashref keyed by L</netdisco_vrf> of each name, of
C<< { complete => 0|1, data => <reader result or undef> } >>. Read anything
needed from the default context before calling this.

Option C<log_as> names the worker in log lines (default C<device>).

=cut

# a record with context kind none, or (defensively) no contexts at all, is read
# in place in the default context like default itself, so attribution-mode
# classes never reconnect
sub _reads_in_default_context {
  my $contexts = $_[0]->{contexts};
  return 1 if not $contexts;
  return (scalar @$contexts and ($contexts->[0]{kind} || '') eq 'none');
}

sub _has_no_context { my $contexts = $_[0]->{contexts}; return ($contexts and not scalar @$contexts) }

sub each_vrf_instance {
  my ($device, $snmp, $instances, $reader, %options) = @_;
  my @named = sort grep { $_ ne 'default' } keys %$instances;
  my @in_place = ('default', grep { _reads_in_default_context($instances->{$_}) } @named);
  my @unserved = grep { _has_no_context($instances->{$_}) } @named;
  my @switched = grep { not _reads_in_default_context($instances->{$_})
                        and not _has_no_context($instances->{$_}) } @named;
  my $log_as = $options{log_as} || 'device';

  my %reads = map {
    (netdisco_vrf($_) => _read_instance($device, $snmp, $_, $instances->{$_}, $reader, 0, \%options))
  } @in_place;

  foreach my $name (@unserved) {
    debug sprintf ' [%s] %s - VRF %s has no context serving its rows', $device->ip, $log_as, $name;
    $reads{ netdisco_vrf($name) } = { complete => 0, data => undef };
  }

  my $guard;
  foreach my $name (@switched) {
    # armed before the switch, so an update() that dies partway still restores
    $guard ||= guard { snmp_vrf_context($snmp, $device, undef) };
    if (not snmp_vrf_context($snmp, $device, $instances->{$name})) {
      debug sprintf ' [%s] %s - VRF %s has no context this session can reach',
        $device->ip, $log_as, $name;
      $reads{ netdisco_vrf($name) } = { complete => 0, data => undef };
      next;
    }
    $reads{ netdisco_vrf($name) }
      = _read_instance($device, $snmp, $name, $instances->{$name}, $reader, 1, \%options);
  }
  return \%reads;
}

sub _read_instance {
  my ($device, $snmp, $name, $instance, $reader, $switched, $options) = @_;
  my $walk_mark = walk_mark($snmp);
  my $data = $reader->($name, $instance, $switched);
  my $complete = ($snmp->vrf_read_complete($name) ? 1 : 0);
  $complete = 0 if scalar incomplete_walks_for($device, $snmp, $walk_mark,
    @{ $options->{walk_methods} || [] });
  if (not $complete) {
    my $error = $snmp->error;
    debug sprintf ' [%s] %s - VRF %s read incomplete, keeping its rows%s',
      $device->ip, ($options->{log_as} || 'device'), $name, (defined $error ? ": $error" : '');
  }
  return { complete => $complete, data => $data };
}

=head1 SEE ALSO

L<SNMP::Info::VRF>

=cut

1;
