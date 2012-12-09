package Netdisco::Util::Connect;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use SNMP::Info;
use Try::Tiny;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  get_device get_port get_iid snmp_connect
/;
our %EXPORT_TAGS = (
  all => [qw/
    get_device get_port get_iid snmp_connect
  /],
);

=head1 Netdisco::Util::Connect

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head2 get_device( $ip )

Given an IP address, returns a L<DBIx::Class::Row> object for the Device in
the Netdisco database. The IP can be for any interface on the device.

Returns C<undef> if the device or interface IP is not known to Netdisco.

=cut

sub get_device {
  my $ip = shift;

  my $alias = schema('netdisco')->resultset('DeviceIp')
    ->search({alias => $ip})->first;
  return if not eval { $alias->ip };

  return schema('netdisco')->resultset('Device')
    ->find({ip => $alias->ip});
}

=head2 get_port( $device, $portname )

=cut

sub get_port {
  my ($device, $portname) = @_;

  # accept either ip or dbic object
  $device = get_device($device)
    if not ref $device;

  my $port = schema('Netdisco')->resultset('DevicePort')
    ->find({ip => $device->ip, port => $portname});

  return $port;
}

=head2 get_iid( $info, $port )

=cut

sub get_iid {
  my ($info, $port) = @_;

  # accept either port name or dbic object
  $port = $port->port if ref $port;

  my $interfaces = $info->interfaces;
  my %rev_if     = reverse %$interfaces;
  my $iid        = $rev_if{$port};

  return $iid;
}

=head2 snmp_connect( $ip )

Given an IP address, returns an L<SNMP::Info> instance configured for and
connected to that device. The IP can be any on the device, and the management
interface will be connected to.

The Netdisco configuration file must have first been loaded using
C<load_nd_config> otherwise the connection will fail (it is required for SNMP
settings).

Returns C<undef> if the connection fails.

=cut

sub snmp_connect {
  my $ip = shift;
  my $nd_config = var('nd_config')->{_};

  # get device details from db
  my $device = get_device($ip)
    or return ();

  # TODO: really only supporing v2c at the moment
  my %snmp_args = (
    DestHost => $device->ip,
    Version => ($device->snmp_ver || $nd_config->{snmpver} || 2),
    Retries => ($nd_config->{snmpretries} || 2),
    Timeout => ($nd_config->{snmptimeout} || 1000000),
    MibDirs => _build_mibdirs(),
    AutoSpecify => 1,
    IgnoreNetSNMPConf => 1,
    Debug => ($ENV{INFO_TRACE} || 0),
  );

  (my $comm = $nd_config->{community_rw}) =~ s/\s+//g;
  my @communities = split /,/, $comm;

  my $info = undef;
  COMMUNITY: foreach my $c (@communities) {
      try {
          $info = SNMP::Info->new(%snmp_args, Community => $c);
          last COMMUNITY if (
            $info
            and (not defined $info->error)
            and length $info->uptime
          );
      };
  }

  return $info;
}

sub _build_mibdirs {
  my $mibhome  = var('nd_config')->{_}->{mibhome};
  (my $mibdirs = var('nd_config')->{_}->{mibdirs}) =~ s/\s+//g;

  $mibdirs =~ s/\$mibhome/$mibhome/g;
  return [ split /,/, $mibdirs ];
}

1;
