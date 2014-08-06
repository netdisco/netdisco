package App::Netdisco::Util::Device;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';
use App::Netdisco::Util::Permission 'check_acl';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  get_device
  check_device_no
  check_device_only
  is_discoverable
  is_arpnipable
  is_macsuckable
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

=head2 check_device_no( $ip, $setting_name )

Given the IP address of a device, returns true if the configuration setting
C<$setting_name> matches that device, else returns false. If the setting
is undefined or empty, then C<check_no> also returns false.

 print "rejected!" if check_no($ip, 'discover_no');

There are several options for what C<$setting_name> can contain:

=over 4

=item *

Hostname, IP address, IP prefix

=item *

IP address range, using a hyphen and no whitespace

=item *

Regular Expression in YAML format which will match the device DNS name, e.g.:

 - !!perl/regexp ^sep0.*$

=item *

C<"model:regex"> - matched against the device model

=item *

C<"vendor:regex"> - matched against the device vendor

=back

To simply match all devices, use "C<any>" or IP Prefix "C<0.0.0.0/0>". All
regular expressions are anchored (that is, they must match the whole string).
To match no devices we recommend an entry of "C<localhost>" in the setting.

=cut

sub check_device_no {
  my ($ip, $setting_name) = @_;
  my $device = get_device($ip) or return 0;

  my $config = setting($setting_name) || [];
  return 0 if not scalar @$config;

  return check_acl($device->ip, $config);
}

=head2 check_device_only( $ip, $setting_name )

Given the IP address of a device, returns true if the configuration setting
C<$setting_name> matches that device, else returns false. If the setting
is undefined or empty, then C<check_only> also returns true.

 print "rejected!" unless check_only($ip, 'discover_only');

There are several options for what C<$setting_name> can contain:

=over 4

=item *

Hostname, IP address, IP prefix

=item *

IP address range, using a hyphen and no whitespace

=item *

Regular Expression in YAML format which will match the device DNS name, e.g.:

 - !!perl/regexp ^sep0.*$

=item *

C<"model:regex"> - matched against the device model

=item *

C<"vendor:regex"> - matched against the device vendor

=back

To simply match all devices, use "C<any>" or IP Prefix "C<0.0.0.0/0>". All
regular expressions are anchored (that is, they must match the whole string).
To match no devices we recommend an entry of "C<localhost>" in the setting.

=cut

sub check_device_only {
  my ($ip, $setting_name) = @_;
  my $device = get_device($ip) or return 0;

  my $config = setting($setting_name) || [];
  return 1 if not scalar @$config;

  return check_acl($device->ip, $config);
}

=head2 is_discoverable( $ip, $device_type? )

Given an IP address, returns C<true> if Netdisco on this host is permitted by
the local configuration to discover the device.

The configuration items C<discover_no> and C<discover_only> are checked
against the given IP.

If C<$device_type> is also given, then C<discover_no_type> will also be
checked.

Returns false if the host is not permitted to discover the target device.

=cut

sub _bail_msg { debug $_[0]; return 0; }

sub is_discoverable {
  my ($ip, $remote_type) = @_;
  my $device = get_device($ip) or return 0;

  if ($remote_type) {
      return _bail_msg("is_discoverable: device matched discover_no_type")
        if scalar grep {$remote_type =~ m/$_/}
                    @{setting('discover_no_type') || []};
  }

  return _bail_msg("is_discoverable: device matched discover_no")
    if check_device_no($device, 'discover_no');

  return _bail_msg("is_discoverable: device failed to match discover_only")
    unless check_device_only($device, 'discover_only');

  # cannot check last_discover for as yet undiscovered devices :-)
  return 1 if not $device->in_storage;

  if ($device->since_last_discover and setting('discover_min_age')
      and $device->since_last_discover < setting('discover_min_age')) {

      return _bail_msg("is_discoverable: time since last discover less than discover_min_age");
  }

  return 1;
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

  return _bail_msg("is_arpnipable: device matched arpnip_no")
    if check_device_no($device, 'arpnip_no');

  return _bail_msg("is_arpnipable: device failed to match arpnip_only")
    unless check_device_only($device, 'arpnip_only');

  return _bail_msg("is_arpnipable: cannot arpnip an undiscovered device")
    if not $device->in_storage;

  if ($device->since_last_arpnip and setting('arpnip_min_age')
      and $device->since_last_arpnip < setting('arpnip_min_age')) {

      return _bail_msg("is_arpnipable: time since last arpnip less than arpnip_min_age");
  }

  return 1;
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

  return _bail_msg("is_macsuckable: device matched macsuck_no")
    if check_device_no($device, 'macsuck_no');

  return _bail_msg("is_macsuckable: device failed to match macsuck_only")
    unless check_device_only($device, 'macsuck_only');

  return _bail_msg("is_macsuckable: cannot macsuck an undiscovered device")
    if not $device->in_storage;

  if ($device->since_last_macsuck and setting('macsuck_min_age')
      and $device->since_last_macsuck < setting('macsuck_min_age')) {

      return _bail_msg("is_macsuckable: time since last macsuck less than macsuck_min_age");
  }

  return 1;
}

1;
