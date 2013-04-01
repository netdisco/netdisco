package App::Netdisco::Util::SNMP;

use Dancer qw/:syntax :script/;
use App::Netdisco::Util::Device 'get_device';

use SNMP::Info;
use Try::Tiny;
use Path::Class 'dir';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  snmp_connect
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::SNMP

=head1 DESCRIPTION

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 FUNCTIONS

=head2 snmp_connect( $ip )

Given an IP address, returns an L<SNMP::Info> instance configured for and
connected to that device. The IP can be any on the device, and the management
interface will be connected to.

Returns C<undef> if the connection fails.

=cut

sub snmp_connect {
  my $ip = shift;

  # get device details from db
  my $device = get_device($ip)
    or return ();

  # TODO: only supporing v2c at the moment
  my %snmp_args = (
    DestHost => $device->ip,
    Version => ($device->snmp_ver || setting('snmpver') || 2),
    Retries => (setting('snmpretries') || 2),
    Timeout => (setting('snmptimeout') || 1000000),
    MibDirs => [ _build_mibdirs() ],
    AutoSpecify => 1,
    IgnoreNetSNMPConf => 1,
    Debug => ($ENV{INFO_TRACE} || 0),
  );

  my $info = undef;
  my $last_comm = 0;
  COMMUNITY: foreach my $c ($device->snmp_comm, @{ setting('community_rw') || []}) {
      next unless defined $c and length $c;
      try {
          $info = SNMP::Info->new(%snmp_args, Community => $c);
          ++$last_comm if (
            $info
            and (not defined $info->error)
            and length $info->uptime
          );
      };
      last COMMUNITY if $last_comm;
  }

  return $info;
}

sub _build_mibdirs {
  return map { dir(setting('mibhome'), $_) }
             @{ setting('mibdirs') || [] };
}

1;
