package App::Netdisco::Util::Device;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use NetAddr::IP::Lite ':lower';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  get_device
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

  my $alias = schema('netdisco')->resultset('DeviceIp')
    ->search({alias => $ip})->first;
  $ip = $alias->ip if defined $alias;

  return schema('netdisco')->resultset('Device')
    ->find_or_new({ip => $ip});
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

sub is_discoverable {
  my ($ip, $remote_type) = @_;
  my $device = get_device($ip) or return 0;

  if ($remote_type) {
      return 0 if
        scalar grep {$remote_type =~ m/$_/}
                    @{setting('discover_no_type') || []};
  }

  my $addr = NetAddr::IP::Lite->new($device->ip);
  my $discover_no   = setting('discover_no') || [];
  my $discover_only = setting('discover_only') || [];

  if (scalar @$discover_no) {
      foreach my $item (@$discover_no) {
          my $ip = NetAddr::IP::Lite->new($item) or return 0;
          return 0 if $ip->contains($addr);
      }
  }

  if (scalar @$discover_only) {
      my $okay = 0;
      foreach my $item (@$discover_only) {
          my $ip = NetAddr::IP::Lite->new($item) or return 0;
          ++$okay if $ip->contains($addr);
      }
      return 0 if not $okay;
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

  my $addr = NetAddr::IP::Lite->new($device->ip);
  my $arpnip_no   = setting('arpnip_no') || [];
  my $arpnip_only = setting('arpnip_only') || [];

  if (scalar @$arpnip_no) {
      foreach my $item (@$arpnip_no) {
          my $ip = NetAddr::IP::Lite->new($item) or return 0;
          return 0 if $ip->contains($addr);
      }
  }

  if (scalar @$arpnip_only) {
      my $okay = 0;
      foreach my $item (@$arpnip_only) {
          my $ip = NetAddr::IP::Lite->new($item) or return 0;
          ++$okay if $ip->contains($addr);
      }
      return 0 if not $okay;
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

  my $addr = NetAddr::IP::Lite->new($device->ip);
  my $macsuck_no   = setting('macsuck_no') || [];
  my $macsuck_only = setting('macsuck_only') || [];

  if (scalar @$macsuck_no) {
      foreach my $item (@$macsuck_no) {
          my $ip = NetAddr::IP::Lite->new($item) or return 0;
          return 0 if $ip->contains($addr);
      }
  }

  if (scalar @$macsuck_only) {
      my $okay = 0;
      foreach my $item (@$macsuck_only) {
          my $ip = NetAddr::IP::Lite->new($item) or return 0;
          ++$okay if $ip->contains($addr);
      }
      return 0 if not $okay;
  }

  return 1;
}

1;
