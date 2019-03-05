package App::Netdisco::Util::Device;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';
use App::Netdisco::Util::Permission qw/check_acl_no check_acl_only/;

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
simply returned.

If the device or interface IP is not known to Netdisco a new Device object is
created for the IP, and returned. This object is in-memory only and not yet
stored to the database.

=cut

sub get_device {
  my $ip = shift;
  return unless $ip;

  # naive check for existing DBIC object
  return $ip if ref $ip;

  # in case the management IP of one device is in use on another device,
  # we first try to get an exact match for the IP as mgmt interface.
  my $alias =
    schema('netdisco')->resultset('DeviceIp')->find($ip, $ip)
    ||
    schema('netdisco')->resultset('DeviceIp')->search({alias => $ip})->first;
  $ip = $alias->ip if defined $alias;

  return schema('netdisco')->resultset('Device')->with_times
    ->find_or_new({ip => $ip});
}

=head2 delete_device( $ip, $archive? )

Given an IP address, deletes the device from Netdisco, including all related
data such as logs and nodes. If the C<$archive> parameter is true, then nodes
will be maintained in an archive state.

Returns true if the transaction completes, else returns false.

=cut

sub delete_device {
  my ($ip, $archive, $log) = @_;
  my $device = get_device($ip) or return 0;
  return 0 if not $device->in_storage;

  my $happy = 0;
  schema('netdisco')->txn_do(sub {
    # will delete everything related too...
    schema('netdisco')->resultset('Device')
      ->search({ ip => $device->ip })->delete({archive_nodes => $archive});

    schema('netdisco')->resultset('UserLog')->create({
      username => session('logged_in_user'),
      userip => scalar eval {request->remote_address},
      event => (sprintf "Delete device %s", $device->ip),
      details => $log,
    });

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
  schema('netdisco')->txn_do(sub {
    $device->renumber($new_ip)
      or die "cannot renumber to: $new_ip"; # rollback

    schema('netdisco')->resultset('UserLog')->create({
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

Returns false if the host is not permitted to discover the target device.

=cut

sub is_discoverable {
  my ($ip, $remote_type, $remote_cap) = @_;
  my $device = get_device($ip) or return 0;
  $remote_type ||= '';
  $remote_cap  ||= [];

  return _bail_msg("is_discoverable: $device matches wap_platforms but discover_waps is not enabled")
    if ((not setting('discover_waps')) and
        (match_to_setting($remote_type, 'wap_platforms') or
         scalar grep {match_to_setting($_, 'wap_capabilities')} @$remote_cap));

  return _bail_msg("is_discoverable: $device matches phone_platforms but discover_phones is not enabled")
    if ((not setting('discover_phones')) and
        (match_to_setting($remote_type, 'phone_platforms') or
         scalar grep {match_to_setting($_, 'phone_capabilities')} @$remote_cap));

  return _bail_msg("is_discoverable: $device matched discover_no_type")
    if (match_to_setting($remote_type, 'discover_no_type'));

  return _bail_msg("is_discoverable: $device matched discover_no")
    if check_acl_no($device, 'discover_no');

  return _bail_msg("is_discoverable: $device failed to match discover_only")
    unless check_acl_only($device, 'discover_only');

  return 1;
}

=head2 is_discoverable_now( $ip, $device_type? )

Same as C<is_discoverable>, but also checks the last_discover field if the
device is in storage, and returns false if that host has been too recently
discovered.

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

Returns false if the host is not permitted to arpnip the target device.

=cut

sub is_arpnipable {
  my $ip = shift;
  my $device = get_device($ip) or return 0;

  return _bail_msg("is_arpnipable: $device matched arpnip_no")
    if check_acl_no($device, 'arpnip_no');

  return _bail_msg("is_arpnipable: $device failed to match arpnip_only")
    unless check_acl_only($device, 'arpnip_only');

  return 1;
}

=head2 is_arpnipable_now( $ip )

Same as C<is_arpnipable>, but also checks the last_arpnip field if the
device is in storage, and returns false if that host has been too recently
arpnipped.

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

Returns false if the host is not permitted to macsuck the target device.

=cut

sub is_macsuckable {
  my $ip = shift;
  my $device = get_device($ip) or return 0;

  return _bail_msg("is_macsuckable: $device matched macsuck_no")
    if check_acl_no($device, 'macsuck_no');

  return _bail_msg("is_macsuckable: $device failed to match macsuck_only")
    unless check_acl_only($device, 'macsuck_only');

  return 1;
}

=head2 is_macsuckable_now( $ip )

Same as C<is_macsuckable>, but also checks the last_macsuck field if the
device is in storage, and returns false if that host has been too recently
macsucked.

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

1;
