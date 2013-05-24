package App::Netdisco::Util::Macsuck;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::DB::ExplicitLocking ':modes';
use App::Netdisco::Util::PortMAC ':all';
use NetAddr::IP::Lite ':lower';
use Time::HiRes 'gettimeofday';
use Net::MAC;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/ do_macsuck /;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::Macsuck

=head1 DESCRIPTION

Helper subroutine to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 do_macsuck( $device, $snmp )

Given a Device database object, and a working SNMP connection, connect to a
device and discover the MAC addresses listed against each physical port
without a neighbor.

If the device has VLANs, C<do_macsuck> will walk each VALN to get the MAC
addresses from there.

It will also gather wireless client information if C<store_wireless_client>
configuration setting is enabled.

=cut

sub do_macsuck {
  my ($device, $snmp) = @_;

  unless ($device->in_storage) {
      debug sprintf ' [%s] macsuck - skipping device not yet discovered', $device->ip;
      return;
  }

  my $port_macs = get_port_macs($device);
  my $ports = $device->ports;

}

1;
