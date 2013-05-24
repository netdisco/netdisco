package App::Netdisco::Util::PortMAC;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/ get_port_macs /;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::PortMAC

=head1 DESCRIPTION

Helper subroutine to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 get_port_macs( $device )

Returns a Hash reference of C<< { MAC => IP } >> for all interface MAC
addresses on a device.

=cut

sub get_port_macs {
  my $device = shift;
  my $port_macs = {};

  unless ($device->in_storage) {
      debug sprintf ' [%s] get_port_macs - skipping device not yet discovered',
        $device->ip;
      return $port_macs;
  }

  my $dp_macs = schema('netdisco')->resultset('DevicePort')
    ->search({ mac => { '!=' => undef} });
  while (my $r = $dp_macs->next) {
      $port_macs->{ $r->mac } = $r->ip;
  }

  my $d_macs = schema('netdisco')->resultset('Device')
    ->search({ mac => { '!=' => undef} });
  while (my $r = $d_macs->next) {
      $port_macs->{ $r->mac } = $r->ip;
  }

  return $port_macs;
}

1;
