package App::Netdisco::Util::SNMP;

use Dancer qw/:syntax :script/;
use App::Netdisco::Util::Device 'get_device';

use SNMP::Info;
use Try::Tiny;
use Path::Class 'dir';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  snmp_connect snmp_connect_rw snmp_comm_reindex
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::SNMP

=head1 DESCRIPTION

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 snmp_connect( $ip )

Given an IP address, returns an L<SNMP::Info> instance configured for and
connected to that device. The IP can be any on the device, and the management
interface will be connected to.

If the device is known to Netdisco and there is a cached SNMP community
string, this will be tried first, and then other community string(s) from the
application configuration will be tried.

Returns C<undef> if the connection fails.

=cut

sub snmp_connect { _snmp_connect_generic(@_, 'community') }

=head2 snmp_connect_rw( $ip )

Same as C<snmp_connect> but uses the read-write community string(s) from the
application configuration file.

Returns C<undef> if the connection fails.

=cut

sub snmp_connect_rw { _snmp_connect_generic(@_, 'community_rw') }

sub _snmp_connect_generic {
  my $ip = shift;

  # get device details from db
  my $device = get_device($ip);

  # TODO: only supporing v2c at the moment
  my %snmp_args = (
    DestHost => $device->ip,
    Retries => (setting('snmpretries') || 2),
    Timeout => (setting('snmptimeout') || 1000000),
    MibDirs => [ _build_mibdirs() ],
    IgnoreNetSNMPConf => 1,
    Debug => ($ENV{INFO_TRACE} || 0),
  );

  # TODO: add version force support
  # use existing SNMP version or try 2, 1
  my @versions = (($device->snmp_ver || setting('snmpver') || 2));
  push @versions, 1;

  # use existing or new device class
  my @classes = ('SNMP::Info');
  if ($device->snmp_class) {
    unshift @classes, $device->snmp_class;
  }
  else {
    $snmp_args{AutoSpecity} = 1;
  }

  # get the community string(s)
  my $comm_type = pop;
  my @communities = @{ setting($comm_type) || []};
  unshift @communities, $device->snmp_comm
    if defined $device->snmp_comm
       and defined $comm_type and $comm_type eq 'community';

  my $info = undef;
  VERSION: foreach my $ver (@versions) {
      next unless length $ver;

      CLASS: foreach my $class (@classes) {
          next unless length $class;

          COMMUNITY: foreach my $comm (@communities) {
              next unless length $comm;

              $info = _try_connect($ver, $class, $comm, \%snmp_args)
                and last VERSION;
          }
      }
  }

  return $info;
}

sub _try_connect {
  my ($ver, $class, $comm, $snmp_args) = @_;
  my $info = undef;

  try {
      debug
        sprintf '[%s] try_connect with ver: %s, class: %s, comm: %s',
        $snmp_args->{DestHost}, $ver, $class, $comm;
      eval "require $class";

      $info = $class->new(%$snmp_args, Version => $ver, Community => $comm);
      undef $info unless (
        (not defined $info->error)
        and defined $info->uptime
        and ($info->layers or $info->description)
        and $info->class
      );

      # first time a device is discovered, re-instantiate into specific class
      if ($info and $info->device_type ne $class) {
          $class = $info->device_type;
          debug
            sprintf '[%s] try_connect with ver: %s, new class: %s, comm: %s',
            $snmp_args->{DestHost}, $ver, $class, $comm;

          eval "require $class";
          $info = $class->new(%$snmp_args, Version => $ver, Community => $comm);
      }
  }
  catch {
      debug $_;
  };

  return $info;
}

sub _build_mibdirs {
  my $home = (setting('mibhome') || dir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'netdisco-mibs'));
  return map { dir($home, $_) }
             @{ setting('mibdirs') || _get_mibdirs_content($home) };
}

sub _get_mibdirs_content {
  my $home = shift;
  warning 'Netdisco SNMP work will be slow - loading ALL MIBs. Consider setting mibdirs.';
  my @list = map {s|$home/||; $_} grep {-d} glob("$home/*");
  return \@list;
}

=head2 snmp_comm_reindex( $snmp, $vlan )

Takes an established L<SNMP::Info> instance and makes a fresh connection using
community indexing, with the given C<$vlan> ID. Works for all SNMP versions.

=cut

sub snmp_comm_reindex {
  my ($snmp, $vlan) = @_;

  my $ver  = $snmp->snmp_ver;
  my $comm = $snmp->snmp_comm;

  if ($ver == 3) {
      $snmp->update(Context => "vlan-$vlan");
  }
  else {
      $snmp->update(Community => $comm . '@' . $vlan);
  }
}

1;
