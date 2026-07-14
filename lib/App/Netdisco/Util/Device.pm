package App::Netdisco::Util::Device;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';
use App::Netdisco::Util::Permission qw/acl_matches acl_matches_only/;

use List::MoreUtils ();
use File::Spec::Functions qw(catdir catfile);
use File::Path 'make_path';
use Scalar::Util 'blessed';
use NetAddr::IP;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  get_device
  delete_device
  renumber_device
  match_to_setting
  is_discoverable is_discoverable_now
  is_arpnipable   is_arpnipable_now
  is_macsuckable  is_macsuckable_now
  get_denied_actions
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::Device

=head1 DESCRIPTION

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 get_device( $ip )

Given an IP address, returns a L<DBIx::Class::Row> object for the Device in
the Netdisco database. The IP can be for any interface on the device.

If for any reason C<$ip> is already a C<DBIx::Class> Device object, then it is
simply returned. If C<$ip> can C<addr> or C<ip> then those methods are called
to get an IP address to locate in the database.

If the device or interface IP is not known to Netdisco a new Device object is
created for the IP, and returned. This object is in-memory only and not yet
stored to the database.

=cut

sub get_device {
  my $ip = shift;
  return unless $ip;

  if (blessed $ip) {
    return $ip if blessed $ip eq 'App::Netdisco::DB::Result::Device';

    if ($ip->can('addr')) {
        $ip = $ip->addr;
    }
    elsif ($ip->can('ip')) {
        $ip = $ip->ip;
    }
    else {
        die sprintf 'unknown class %s passed to get_device', blessed $ip;
    }
  }

  die 'reference passed to get_device' if ref $ip;

  # in case the management IP of one device is in use on another device,
  # we first try to get an exact match for the IP as mgmt interface.
  my $alias =
    schema(vars->{'tenant'})->resultset('DeviceIp')->find($ip, $ip)
    ||
    schema(vars->{'tenant'})->resultset('DeviceIp')->search({alias => $ip})->first;
  $ip = $alias->ip if defined $alias;

  return schema(vars->{'tenant'})->resultset('Device')->with_times
    ->find_or_new({ip => $ip});
}

=head2 delete_device( $ip, $archive? )

Given an IP address, deletes the device from Netdisco, including all related
data such as logs and nodes. If the C<$archive> parameter is true, then nodes
will be maintained in an archive state.

Returns true if the transaction completes, else returns false.

=cut

sub delete_device {
  my ($ip, $archive) = @_;
  my $device = get_device($ip) or return 0;
  return 0 if not $device->in_storage;

  my $happy = 0;
  schema(vars->{'tenant'})->txn_do(sub {
    # will delete everything related too...
    schema(vars->{'tenant'})->resultset('Device')
      ->search({ ip => $device->ip })->delete({archive_nodes => $archive});

    $happy = 1;
  });

  return $happy;
}

=head2 renumber_device( $current_ip, $new_ip )

Will update all records in Netdisco referring to the device with
C<$current_ip> to use C<$new_ip> instead, followed by renumbering the
device itself.

Returns true if the transaction completes, else returns false.

=cut

sub renumber_device {
  my ($ip, $new_ip) = @_;
  my $device = get_device($ip) or return 0;
  return 0 if not $device->in_storage;

  my $happy = 0;
  schema(vars->{'tenant'})->txn_do(sub {
    $device->renumber($new_ip)
      or die "cannot renumber to: $new_ip"; # rollback

    schema(vars->{'tenant'})->resultset('UserLog')->create({
      username => session('logged_in_user'),
      userip => scalar eval {request->remote_address},
      event => (sprintf "Renumber device %s to %s", $ip, $new_ip),
    });

    $happy = 1;
  });

  return $happy;
}

=head2 match_to_setting( $type, $setting_name )

Given a C<$type> (which may be any text value), returns true if any of the
list of regular expressions in C<$setting_name> is matched, otherwise returns
false.

=cut

sub match_to_setting {
    my ($type, $setting_name) = @_;
    return 0 unless $type and $setting_name;
    return (scalar grep {$type =~ m/$_/}
                        @{setting($setting_name) || []});
}

sub _bail_msg { debug $_[0]; return 0; }

=head2 is_discoverable( $ip, [$device_type, \@device_capabilities]? )

Given an IP address, returns C<true> if Netdisco on this host is permitted by
the local configuration to discover the device.

The configuration items C<discover_no> and C<discover_only> are checked
against the given IP.

If C<$device_type> is also given, then C<discover_no_type> will be checked.
Also respects C<discover_phones> and C<discover_waps> if either are set to
false.

Also checks if the device is a pseudo device and no offline cache exists.

Returns false if the host is not permitted to discover the target device.

=cut

sub is_discoverable {
  my ($ip, $remote_type, $remote_cap) = @_;
  my $device = get_device($ip) or return 0;
  $remote_type ||= '';
  $remote_cap  ||= [];

  return _bail_msg("is_discoverable: $device is pseudo-device without offline cache")
    if $device->is_pseudo and not $device->oids->count;

  return _bail_msg("is_discoverable: $device matches wap_platforms but discover_waps is not enabled")
    if ((not setting('discover_waps')) and
        match_to_setting($remote_type, 'wap_platforms'));

  return _bail_msg("is_discoverable: $device matches wap_capabilities but discover_waps is not enabled")
    if ((not setting('discover_waps')) and
        (scalar grep {match_to_setting($_, 'wap_capabilities')} @$remote_cap));

  return _bail_msg("is_discoverable: $device matches phone_platforms but discover_phones is not enabled")
    if ((not setting('discover_phones')) and
        match_to_setting($remote_type, 'phone_platforms'));

  return _bail_msg("is_discoverable: $device matches phone_capabilities but discover_phones is not enabled")
    if ((not setting('discover_phones')) and
        (scalar grep {match_to_setting($_, 'phone_capabilities')} @$remote_cap));

  return _bail_msg("is_discoverable: $device matched discover_no_type")
    if (match_to_setting($remote_type, 'discover_no_type'));

  return _bail_msg("is_discoverable: $device matched discover_no")
    if acl_matches($device, 'discover_no');

  return _bail_msg("is_discoverable: $device failed to match discover_only")
    unless acl_matches_only($device, 'discover_only');

  return 1;
}

=head2 is_discoverable_now( $ip, $device_type? )

Same as C<is_discoverable>, but also compares the C<last_discover> field
of the C<device> to the C<discover_min_age> configuration.

Returns false if the host is not permitted to discover the target device.

=cut

sub is_discoverable_now {
  my ($ip, $remote_type) = @_;
  my $device = get_device($ip) or return 0;

  if ($device->in_storage
      and $device->since_last_discover and setting('discover_min_age')
      and $device->since_last_discover < setting('discover_min_age')) {

      return _bail_msg("is_discoverable: $device last discover < discover_min_age");
  }

  return is_discoverable(@_);
}

=head2 is_arpnipable( $ip )

Given an IP address, returns C<true> if Netdisco on this host is permitted by
the local configuration to arpnip the device.

The configuration items C<arpnip_no> and C<arpnip_only> are checked
against the given IP.

Also checks if the device reports layer 3 capability, or matches
C<force_arpnip> or C<ignore_layers>.

Returns false if the host is not permitted to arpnip the target device.

=cut

sub is_arpnipable {
  my $ip = shift;
  my $device = get_device($ip) or return 0;

  return _bail_msg("is_arpnipable: $device has no layer 3 capability")
    if ($device->in_storage() and not ($device->has_layer(3)
                                       or acl_matches($device, 'force_arpnip')
                                       or acl_matches($device, 'ignore_layers')));

  return _bail_msg("is_arpnipable: $device matched arpnip_no")
    if acl_matches($device, 'arpnip_no');

  return _bail_msg("is_arpnipable: $device failed to match arpnip_only")
    unless acl_matches_only($device, 'arpnip_only');

  return 1;
}

=head2 is_arpnipable_now( $ip )

Same as C<is_arpnipable>, but also compares the C<last_arpnip> field
of the C<device> to the C<arpnip_min_age> configuration.

Returns false if the host is not permitted to arpnip the target device.

=cut

sub is_arpnipable_now {
  my ($ip) = @_;
  my $device = get_device($ip) or return 0;

  if ($device->in_storage
      and $device->since_last_arpnip and setting('arpnip_min_age')
      and $device->since_last_arpnip < setting('arpnip_min_age')) {

      return _bail_msg("is_arpnipable: $device last arpnip < arpnip_min_age");
  }

  return is_arpnipable(@_);
}

=head2 is_macsuckable( $ip )

Given an IP address, returns C<true> if Netdisco on this host is permitted by
the local configuration to macsuck the device.

The configuration items C<macsuck_no> and C<macsuck_only> are checked
against the given IP.

Also checks if the device reports layer 2 capability, or matches
C<force_macsuck> or C<ignore_layers>.

Returns false if the host is not permitted to macsuck the target device.

=cut

sub is_macsuckable {
  my $ip = shift;
  my $device = get_device($ip) or return 0;

  return _bail_msg("is_macsuckable: $device has no layer 2 capability")
    if ($device->in_storage() and not ($device->has_layer(2)
                                       or acl_matches($device, 'force_macsuck')
                                       or acl_matches($device, 'ignore_layers')));

  return _bail_msg("is_macsuckable: $device matched macsuck_no")
    if acl_matches($device, 'macsuck_no');

  return _bail_msg("is_macsuckable: $device matched macsuck_unsupported")
    if acl_matches($device, 'macsuck_unsupported');

  return _bail_msg("is_macsuckable: $device failed to match macsuck_only")
    unless acl_matches_only($device, 'macsuck_only');

  return 1;
}

=head2 is_macsuckable_now( $ip )

Same as C<is_macsuckable>, but also compares the C<last_macsuck> field
of the C<device> to the C<macsuck_min_age> configuration.

Returns false if the host is not permitted to macsuck the target device.

=cut

sub is_macsuckable_now {
  my ($ip) = @_;
  my $device = get_device($ip) or return 0;

  if ($device->in_storage
      and $device->since_last_macsuck and setting('macsuck_min_age')
      and $device->since_last_macsuck < setting('macsuck_min_age')) {

      return _bail_msg("is_macsuckable: $device last macsuck < macsuck_min_age");
  }

  return is_macsuckable(@_);
}

=head2 get_denied_actions( $device )

Checks configured ACLs for the device on this backend and returns list
of actions which are denied.

=cut

sub get_denied_actions {
  my $device = shift;
  my @badactions = ();
  return @badactions unless $device;
  $device = get_device($device); # might be no-op but is done in is_* anyway

  if ($device->is_pseudo) {
      # always let pseudo devices do contact|location|portname|snapshot|delete
      # and additionally if there's a snapshot cache, is_discoverable will let
      # them do all other discover and high prio actions
      push @badactions, ('discover', grep { $_ !~ m/^(?:contact|location|portname|snapshot|delete)$/ }
                                          @{ setting('job_prio')->{high} })
        if not is_discoverable($device);
  }
  else {
      # #1335 always let delete run
      push @badactions, ('discover', grep { $_ !~ m/^(?:delete)$/ }
                                          @{ setting('job_prio')->{high} })
        if not is_discoverable($device);
  }

  push @badactions, (qw/macsuck nbtstat/)
    if not is_macsuckable($device);

  push @badactions, 'arpnip'
    if not is_arpnipable($device);

  # add pseudo-actions for schedule entries with ACLs
  my $schedule = setting('schedule') || {};
  foreach my $label (keys %$schedule) {
      my $sched = $schedule->{$label} || next;
      next unless $sched->{only} or $sched->{no};

      my $action = $sched->{action} || $label;
      my $pseudo_action = "scheduled-$label";

      # if this action is denied in global config then schedule should not run
      if (scalar grep {$_ eq $action} @badactions) {
          push @badactions, $pseudo_action;
          next;
      }

      my $net = NetAddr::IP->new($sched->{device});
      next if ($sched->{device}
        and (!$net or $net->num == 0 or $net->addr eq '0.0.0.0'));

      push @badactions, $pseudo_action
        if $sched->{device} and not acl_matches_only($device, $net->cidr);
      push @badactions, $pseudo_action
        if $sched->{no} and acl_matches($device, $sched->{no});
      push @badactions, $pseudo_action
        if $sched->{only} and not acl_matches_only($device, $sched->{only});
  }

  return List::MoreUtils::uniq @badactions;
}

1;
