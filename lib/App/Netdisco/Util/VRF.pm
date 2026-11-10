package App::Netdisco::Util::VRF;

use strict;
use warnings;

use Dancer qw/:syntax :script !pass/;
use App::Netdisco::Util::Permission 'acl_matches';
use App::Netdisco::Util::SNMP qw/snmp_vrf_context walk_mark incomplete_walks_for/;
use Scope::Guard 'guard';
use Scalar::Util qw/blessed refaddr/;
use App::Netdisco::Transport::SNMP ();

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  vrf_collection_enabled
  vrf_skip_test
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

True only when the C<store_vrfs> setting is on, the device does not match
C<skip_vrf_devices>, and the device is not a pseudo device. A pseudo device may
be read from a snapshot, so every worker treats it as if C<store_vrfs> were off,
whether it is read from a snapshot or live.

=cut

sub vrf_collection_enabled {
  my $device = shift;
  return 0 unless setting('store_vrfs');
  # a context switch is an update(), which clears SNMP::Info's cache: for a
  # snapshot read offline that cache is the snapshot. Transport::SNMP marks a
  # device pseudo when it loads one, so for a device not yet stored this is
  # only reliable after reader_for
  return 0 if $device->is_pseudo;
  return (not acl_matches($device, 'skip_vrf_devices'));
}

=head2 vrf_skip_test( $device )

Returns a test, C<< $skipped->($local_name) >>, true when C<vrf_no_devicevrfs>
skips that VRF on C<$device>. Build it once, before a loop: the device is
matched against the setting's keys here, and each name's answer is kept, so
the test costs one ACL check per distinct name however often it is asked.
Never true for the default table, whichever of C<default> or the empty string
names it.

C<vrf_no_devicevrfs> is a dictionary, or a list of them, as
C<macsuck_no_deviceports>: each key is an ACL matching devices, its value an
ACL matching the VRFs to skip on them. A VRF is matched as C<vrf:E<lt>regexE<gt>>,
anchored at both ends, so C<.>, C<+> and C<(> are live; C<(?i)> ignores case.

  vrf_no_devicevrfs:
    'group:__ANY__': ['vrf:(?i)mgmt', 'vrf:lab-.*']
    '192.0.2.1': 'vrf:cust:a'

A hostname or regex rule in a key costs a DNS lookup each time a test is
built, which is a few times per job. A value rule without a property (a bare
name) or a regex object never matches a VRF, so each warns once.

=cut

sub vrf_skip_test {
  my $device = shift;
  my @vrf_acls = _vrf_acls_for($device);
  my %answer;

  return sub {
    my $name = shift;
    return 0 if not defined $name or $name eq '' or $name eq 'default';
    return 0 unless scalar @vrf_acls;
    $answer{$name} //= ((scalar grep { acl_matches({ vrf => $name }, $_) } @vrf_acls) ? 1 : 0);
    return $answer{$name};
  };
}

sub _vrf_acls_for {
  my $device = shift;
  my @acls;
  foreach my $map (_skip_maps()) {
    foreach my $key (sort keys %$map) {
      next unless $key and $map->{$key};
      _warn_unmatchable_rules($map->{$key});
      push @acls, $map->{$key} if acl_matches($device, $key);
    }
  }
  return @acls;
}

my %warned;

sub _skip_maps {
  my $setting = setting('vrf_no_devicevrfs');
  return ($setting) if ref {} eq ref $setting;
  return () unless ref [] eq ref $setting;
  foreach my $entry (grep { ref {} ne ref $_ } @$setting) {
    next if $warned{"entry:" . ($entry // '')}++;
    warning sprintf 'vrf_no_devicevrfs entry "%s" is ignored: each entry maps a device ACL to VRF rules. Write it as \'<device>\': \'vrf:<name>\'', $entry // '';
  }
  return grep { ref {} eq ref $_ } @$setting;
}

# check_acl reads a bare string as an address or hostname, and a regex object
# as a pattern for the device's DNS name, so neither can match { vrf => ... }
sub _warn_unmatchable_rules {
  my $rules = shift;
  foreach my $rule (ref [] eq ref $rules ? @$rules : ($rules)) {
    next if not defined $rule or $warned{"rule:$rule"};
    my $plain = ref $rule ? '' : $rule;
    $plain =~ s/^!//;
    next if $plain eq 'op:and' or ($plain =~ m/^([^:]+):/ and $1 !~ m/^[a-f0-9]+$/i);
    $warned{"rule:$rule"}++;
    warning sprintf 'vrf_no_devicevrfs rule "%s" matches no VRF. Write a VRF as vrf:<name> or vrf:<regex>', $rule;
  }
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
by L</vrf_skip_test>, or C<undef> when collection is disabled for the device or
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
  my $skipped = vrf_skip_test($device);
  return { map { ($_ => $instances->{$_}) }
           grep { not $skipped->($_) } keys %$instances };
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

Where the default read is partial only because other instances leak into it
(C<< $snmp->vrf_read_leaked('default') >>, SNMP::Info 3.985001, so far only
Juniper's virtual routers), each of those instances' ports are read with
C<i_vrf()> in its own context. Once every one of them was read whole, the
session returns to the default context, hands the ports to
C<vrf_exclude_ports()> and reads C<default> a second time, which replaces the
first read. Otherwise the first, partial read stands.

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

  # a partial default read is reported only once it is known not to be
  # completed below, so a log never says rows are kept that then retire
  my $default_partial;
  my %reads = map {
    (netdisco_vrf($_) => _read_instance($device, $snmp, $_, $instances->{$_}, $reader, 0, \%options,
      ($_ eq 'default' ? \$default_partial : undef)))
  } @in_place;
  my $leaked = _leaked_instances($snmp, $reads{''});
  debug $default_partial if defined $default_partial and not $leaked;
  my %leaked_ports;

  foreach my $name (@unserved) {
    debug sprintf ' [%s] %s - VRF %s has no context serving its rows', $device->ip, $log_as, $name;
    $reads{ netdisco_vrf($name) } = { complete => 0, data => undef };
  }

  my $guard;
  foreach my $name (@switched) {
    # armed before the switch, so an update() that dies partway still restores
    $guard ||= guard { _return_to_default($device, $snmp, $log_as) };
    my $switched = snmp_vrf_context($snmp, $device, $instances->{$name});
    my $unread = (not defined $switched) ? 'has no context this session can reach'
      : (not $switched) ? 'could not be switched to, update() failed'. _error_suffix($snmp)
      : (not _context_answers($snmp)) ? 'context did not answer, so it was not read' : undef;
    if ($unread) {
      debug sprintf ' [%s] %s - VRF %s %s', $device->ip, $log_as, $name, $unread;
      $reads{ netdisco_vrf($name) } = { complete => 0, data => undef };
      next;
    }
    $reads{ netdisco_vrf($name) }
      = _read_instance($device, $snmp, $name, $instances->{$name}, $reader, 1, \%options);
    $leaked_ports{$name} = _leaked_ports($device, $snmp)
      if $leaked and $reads{ netdisco_vrf($name) }{complete} and grep { $_ eq $name } @$leaked;
  }
  _complete_default_read($device, $snmp, $instances, $reader, \%reads, $leaked,
    \%leaked_ports, $guard, \%options) if $leaked;
  return \%reads;
}

# the instances SNMP::Info names as mixed into a partial default read; asked
# in the default context, after its readers, as vrf_read_leaked requires
sub _leaked_instances {
  my ($snmp, $default_read) = @_;
  return undef if not $default_read or $default_read->{complete};
  return undef unless $snmp->can('vrf_read_leaked') and $snmp->can('vrf_exclude_ports');
  my $leaked = $snmp->vrf_read_leaked('default');
  return (ref [] eq ref $leaked and scalar @$leaked) ? $leaked : undef;
}

# the whole port set of the instance whose context the session is in, or undef
# when the walk was short: a partial set would let its rows back into default
sub _leaked_ports {
  my ($device, $snmp) = @_;
  my $walk_mark = walk_mark($snmp);
  my $i_vrf = $snmp->i_vrf;
  return undef if scalar incomplete_walks_for($device, $snmp, $walk_mark, 'i_vrf');
  return undef unless ref {} eq ref $i_vrf and scalar keys %$i_vrf;
  return [ sort { $a <=> $b } keys %$i_vrf ];
}

# exclusions are recorded after the return to default because update() clears
# SNMP::Info's cache, exclusions included
sub _complete_default_read {
  my ($device, $snmp, $instances, $reader, $reads, $leaked, $ports, $guard, $options) = @_;
  my $log_as = $options->{log_as} || 'device';
  my @skipped = grep { not $instances->{$_} } @$leaked;
  if (@skipped) {
    debug sprintf ' [%s] %s - default read stays partial: %s is not collected (vrf_no_devicevrfs)',
      $device->ip, $log_as, join(', ', @skipped);
    return;
  }
  my @unread = grep { not $ports->{$_} } @$leaked;
  if (@unread) {
    debug sprintf ' [%s] %s - default read stays partial: %s not read whole in their own context',
      $device->ip, $log_as, join(', ', @unread);
    return;
  }
  return unless snmp_vrf_context($snmp, $device, undef);
  $guard->dismiss if $guard;

  foreach my $name (@$leaked) {
    next if $snmp->vrf_exclude_ports($name, $ports->{$name});
    debug sprintf ' [%s] %s - default read stays partial: SNMP::Info refused the ports of %s%s',
      $device->ip, $log_as, $name, _error_suffix($snmp);
    return;
  }
  $reads->{''} = _read_instance($device, $snmp, 'default', $instances->{default}, $reader, 0, $options);
}

# the reader is cached for the job, so a session stuck in a VRF context would
# feed every later worker that VRF's rows as the default table's
sub _return_to_default {
  my ($device, $snmp, $log_as) = @_;
  return if snmp_vrf_context($snmp, $device, undef);
  warning sprintf ' [%s] %s - could not return to the default context, so the SNMP session is dropped%s',
    $device->ip, $log_as, _error_suffix($snmp);
  my $readers = App::Netdisco::Transport::SNMP->instance->readers;
  delete $readers->{ $device->ip }
    if $readers and (refaddr($readers->{ $device->ip }) || 0) == refaddr($snmp);
}

sub _error_suffix {
  my $error = $_[0]->error;
  return (defined $error and length $error) ? ": $error" : '';
}

# one get before the reader: a reader walks attribute after attribute, and a
# context the device does not serve costs each of them the full timeout. Only a
# timeout counts; an error or noSuchObject is an answer
sub _context_answers {
  my $session = $_[0]->session;
  # no session to ask is no evidence of a dead context
  return 1 unless blessed $session and $session->can('get');
  $session->get('.1.3.6.1.2.1.1.3.0');
  return (($session->{ErrorStr} || '') !~ m/timeout/i);
}

sub _read_instance {
  my ($device, $snmp, $name, $instance, $reader, $switched, $options, $deferred_log) = @_;
  my $walk_mark = walk_mark($snmp);
  # error() returns any error pending since it was last read; discard it, so
  # the one logged below is one this read set
  $snmp->error;
  my $data = $reader->($name, $instance, $switched);
  my $complete = ($snmp->vrf_read_complete($name) ? 1 : 0);
  $complete = 0 if scalar incomplete_walks_for($device, $snmp, $walk_mark,
    @{ $options->{walk_methods} || [] });
  if (not $complete) {
    my $error = $snmp->error;
    my $line = sprintf ' [%s] %s - VRF %s read incomplete, keeping its rows%s',
      $device->ip, ($options->{log_as} || 'device'), $name, (defined $error ? ": $error" : '');
    if ($deferred_log) { $$deferred_log = $line } else { debug $line }
  }
  return { complete => $complete, data => $data };
}

=head1 SEE ALSO

L<SNMP::Info::VRF>

=cut

1;
