package App::Netdisco::Util::Device;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use NetAddr::IP::Lite ':lower';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  get_device
  check_no
  check_only
  is_discoverable
  is_arpnipable
  can_nodenames
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

  my $alias = schema('netdisco')->resultset('DeviceIp')
    ->search({alias => $ip})->first;
  $ip = $alias->ip if defined $alias;

  return schema('netdisco')->resultset('Device')->with_times
    ->find_or_new({ip => $ip});
}

sub _check_acl {
  my ($ip, $config) = @_;
  my $device = get_device($ip) or return 0;
  my $addr = NetAddr::IP::Lite->new($device->ip);

  foreach my $item (@$config) {
      if ($item =~ m/^(.*)\s*:\s*(.*)$/) {
          my $prop  = $1;
          my $match = $2;

          # if not in storage, we can't do much with device properties
          next unless $device->in_storage;

          # lazy version of vendor: and model:
          if ($device->can($prop) and defined $device->prop
              and $device->prop =~ m/^$match$/) {
              return 1;
          }
          next;
      }

      my $ip = NetAddr::IP::Lite->new($item) or next;
      return 1 if $ip->contains($addr);
  }

  return 0;
}

=head2 check_no( $ip, $setting_name )

Given the IP address of a device, returns true if the configuration setting
C<$setting_name> matches that device, else returns false.

 print "rejected!" if check_no($ip, 'discover_no');

There are several options for what C<$setting_name> can contain:

=over 4

=item *

Hostname, IP address, IP prefix

=item *

C<"model:regex"> - matched against the device model

=item *

C<"vendor:regex"> - matched against the device vendor

=back

To simply match all devices, use "C<any>" or IP Prefix "C<0.0.0.0/0>". All
regular expressions are anchored (that is, they must match the whole string).
To match no devices we recommend an entry of "C<localhost>" in the setting.

=cut

sub check_no {
  my ($ip, $setting_name) = @_;

  my $config = setting($setting_name) || [];
  return 0 unless scalar @$config;

  return _check_acl($ip, $config);
}

=head2 check_only( $ip, $setting_name )

Given the IP address of a device, returns false if the configuration setting
C<$setting_name> matches that device, else returns true.

 print "rejected!" unless check_only($ip, 'discover_only');

There are several options for what C<$setting_name> can contain:

=over 4

=item *

Hostname, IP address, IP prefix

=item *

C<"model:regex"> - matched against the device model

=item *

C<"vendor:regex"> - matched against the device vendor

=back

To simply match all devices, use "C<any>" or IP Prefix "C<0.0.0.0/0>". All
regular expressions are anchored (that is, they must match the whole string).
To match no devices we recommend an entry of "C<localhost>" in the setting.

=cut

sub check_only {
  my ($ip, $setting_name) = @_;

  my $config = setting($setting_name) || [];
  return 1 unless scalar @$config;

  return _check_acl($ip, $config);
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
    if check_no($device, 'discover_no');

  return _bail_msg("is_discoverable: device failed to match discover_only")
    unless check_only($device, 'discover_only');

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
    if check_no($device, 'arpnip_no');

  return _bail_msg("is_arpnipable: device failed to match arpnip_only")
    unless check_only($device, 'arpnip_only');

  return _bail_msg("is_arpnipable: cannot arpnip an undiscovered device")
    if not $device->in_storage;

  if ($device->since_last_arpnip and setting('arpnip_min_age')
      and $device->since_last_arpnip < setting('arpnip_min_age')) {

      return _bail_msg("is_arpnipable: time since last arpnip less than arpnip_min_age");
  }

  return 1;
}

=head2 can_nodenames( $ip )

Given an IP address, returns C<true> if Netdisco on this host is permitted by
the local configuration to resolve Node IPs to DNS names for the device.

The configuration items C<nodenames_no> and C<nodenames_only> are checked
against the given IP.

Returns false if the host is not permitted to do this job for the target
device.

=cut

sub can_nodenames {
  my $ip = shift;
  my $device = get_device($ip) or return 0;

  return _bail_msg("can_nodenames device matched nodenames_no")
    if check_no($device, 'nodenames_no');

  return _bail_msg("can_nodenames: device failed to match nodenames_only")
    unless check_only($device, 'nodenames_only');

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
    if check_no($device, 'macsuck_no');

  return _bail_msg("is_macsuckable: device failed to match macsuck_only")
    unless check_only($device, 'macsuck_only');

  return _bail_msg("is_macsuckable: cannot macsuck an undiscovered device")
    if not $device->in_storage;

  if ($device->since_last_macsuck and setting('macsuck_min_age')
      and $device->since_last_macsuck < setting('macsuck_min_age')) {

      return _bail_msg("is_macsuckable: time since last macsuck less than macsuck_min_age");
  }

  return 1;
}

1;
