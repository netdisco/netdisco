package App::Netdisco::Transport::SNMP;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::SNMP 'get_communities';
use App::Netdisco::Util::Device 'get_device';
use App::Netdisco::Util::Permission ':all';

use SNMP::Info;
use Try::Tiny;
use Module::Load ();
use Path::Class 'dir';
use NetAddr::IP::Lite ':lower';
use List::Util qw/pairkeys pairfirst/;

use base 'Dancer::Object::Singleton';

=head1 NAME

App::Netdisco::Transport::SNMP

=head1 DESCRIPTION

Singleton for SNMP connections. Returns cached L<SNMP::Info> instance for a
given device IP, or else undef. All methods are class methods, for example:

 my $snmp = App::Netdisco::Transport::SNMP->reader_for( ... );

=cut

__PACKAGE__->attributes(qw/ readers writers /);

sub init {
  my ( $class, $self ) = @_;
  $self->readers( {} );
  $self->writers( {} );
  return $self;
}

=head1 reader_for( $ip, $useclass? )

Given an IP address, returns an L<SNMP::Info> instance configured for and
connected to that device. The IP can be any on the device, and the management
interface will be connected to.

If the device is known to Netdisco and there is a cached SNMP community
string, that community will be tried first, and then other community strings
from the application configuration will be tried.

If C<$useclass> is provided, it will be used as the L<SNMP::Info> device
class instead of the class in the Netdisco database.

Returns C<undef> if the connection fails.

=cut

sub reader_for {
  my ($class, $ip, $useclass) = @_;
  my $device = get_device($ip) or return undef;
  my $readers = $class->instance->readers or return undef;
  return $readers->{$device->ip} if exists $readers->{$device->ip};
  debug sprintf 'snmp reader cache warm: [%s]', $device->ip;
  return ($readers->{$device->ip}
    = _snmp_connect_generic('read', $device, $useclass));
}

=head1 test_connection( $ip )

Similar to C<reader_for> but will use the literal IP address passed, and does
not support specifying the device class. The purpose is to test the SNMP
connectivity to the device before a renumber.

Attempts to have no side effect, however there will be a stored SNMP
authentication hint (tag) in the database if the connection is successful.

Returns C<undef> if the connection fails.

=cut

sub test_connection {
  my ($class, $ip) = @_;
  my $addr = NetAddr::IP::Lite->new($ip) or return undef;
  # avoid renumbering to localhost loopbacks
  return undef if $addr->addr eq '0.0.0.0'
                  or check_acl_no($addr->addr, 'group:__LOCAL_ADDRESSES__');
  my $device = schema('netdisco')->resultset('Device')
    ->new_result({ ip => $addr->addr }) or return undef;
  my $readers = $class->instance->readers or return undef;
  return $readers->{$device->ip} if exists $readers->{$device->ip};
  debug sprintf 'snmp reader cache warm: [%s]', $device->ip;
  return ($readers->{$device->ip} = _snmp_connect_generic('read', $device));
}

=head1 writer_for( $ip, $useclass? )

Same as C<reader_for> but uses the read-write community strings from the
application configuration file.

Returns C<undef> if the connection fails.

=cut

sub writer_for {
  my ($class, $ip, $useclass) = @_;
  my $device = get_device($ip) or return undef;
  my $writers = $class->instance->writers or return undef;
  return $writers->{$device->ip} if exists $writers->{$device->ip};
  debug sprintf 'snmp writer cache warm: [%s]', $device->ip;
  return ($writers->{$device->ip}
    = _snmp_connect_generic('write', $device, $useclass));
}

sub _snmp_connect_generic {
  my ($mode, $device, $useclass) = @_;
  $mode ||= 'read';

  my %snmp_args = (
    AutoSpecify => 0,
    DestHost => $device->ip,
    # 0 is falsy. Using || with snmpretries equal to 0 will set retries to 2.
    # check if the setting is 0. If not, use the default value of 2.
    Retries => (setting('snmpretries') || setting('snmpretries') == 0 ? 0 : 2),
    Timeout => (setting('snmptimeout') || 1000000),
    NonIncreasing => (setting('nonincreasing') || 0),
    BulkWalk => ((defined setting('bulkwalk_off') && setting('bulkwalk_off'))
                 ? 0 : 1),
    BulkRepeaters => (setting('bulkwalk_repeaters') || 20),
    MibDirs => [ _build_mibdirs() ],
    IgnoreNetSNMPConf => 1,
    Debug => ($ENV{INFO_TRACE} || 0),
    DebugSNMP => ($ENV{SNMP_TRACE} || 0),
  );

  # an override for RemotePort
  ($snmp_args{RemotePort}) =
    (pairkeys pairfirst { check_acl_no($device, $b) }
      %{setting('snmp_remoteport') || {}}) || 161;

  # an override for bulkwalk
  $snmp_args{BulkWalk} = 0 if check_acl_no($device, 'bulkwalk_no');

  # further protect against buggy Net-SNMP, and disable bulkwalk
  if ($snmp_args{BulkWalk}
      and ($SNMP::VERSION eq '5.0203' || $SNMP::VERSION eq '5.0301')) {

      warning sprintf
        "[%s] turning off BulkWalk due to buggy Net-SNMP - please upgrade!",
        $device->ip;
      $snmp_args{BulkWalk} = 0;
  }

  # get the community string(s)
  my @communities = get_communities($device, $mode);

  # which SNMP versions to try and in what order
  my @versions =
    ( check_acl_no($device->ip, 'snmpforce_v3') ? (3)
    : check_acl_no($device->ip, 'snmpforce_v2') ? (2)
    : check_acl_no($device->ip, 'snmpforce_v1') ? (1)
    : (reverse (1 .. (setting('snmpver') || 3))) );

  # use existing or new device class
  my @classes = ($useclass || 'SNMP::Info');
  if ($device->snmp_class and not $useclass) {
      unshift @classes, $device->snmp_class;
  }

  my $info = undef;
  COMMUNITY: foreach my $comm (@communities) {
      next unless $comm;

      VERSION: foreach my $ver (@versions) {
          next unless $ver;

          next if $ver eq 3 and exists $comm->{community};
          next if $ver ne 3 and !exists $comm->{community};

          CLASS: foreach my $class (@classes) {
              next unless $class;

              my %local_args = (%snmp_args, Version => $ver);
              $info = _try_connect($device, $class, $comm, $mode, \%local_args,
                ($useclass ? 0 : 1) );
              last COMMUNITY if $info;
          }
      }
  }

  return $info;
}

sub _try_connect {
  my ($device, $class, $comm, $mode, $snmp_args, $reclass) = @_;
  my %comm_args = _mk_info_commargs($comm);
  my $debug_comm = '<hidden>';
  if ($ENV{ND2_SHOW_COMMUNITY} || $ENV{SHOW_COMMUNITY}) {
    $debug_comm = ($comm->{community} ||
      (sprintf 'v3:%s:%s/%s', ($comm->{user},
                              ($comm->{auth}->{proto} || 'noAuth'),
                              ($comm->{priv}->{proto} || 'noPriv'))) );
  }
  my $info = undef;

  try {
      debug
        sprintf '[%s:%s] try_connect with ver: %s, class: %s, comm: %s',
          $snmp_args->{DestHost}, $snmp_args->{RemotePort},
          $snmp_args->{Version}, $class, $debug_comm;
      Module::Load::load $class;

      $info = $class->new(%$snmp_args, %comm_args) or return;
      $info = ($mode eq 'read' ? _try_read($info, $device, $comm)
                               : _try_write($info, $device, $comm));

      # first time a device is discovered, re-instantiate into specific class
      if ($reclass and $info and $info->device_type ne $class) {
          $class = $info->device_type;
          debug
            sprintf '[%s:%s] try_connect with ver: %s, new class: %s, comm: %s',
              $snmp_args->{DestHost}, $snmp_args->{RemotePort},
              $snmp_args->{Version}, $class, $debug_comm;

          Module::Load::load $class;
          $info = $class->new(%$snmp_args, %comm_args);
      }
  }
  catch {
      debug $_;
  };

  return $info;
}

sub _try_read {
  my ($info, $device, $comm) = @_;

  return undef unless (
    (not defined $info->error)
    and defined $info->uptime
    and ($info->layers or $info->description)
    and $info->class
  );

  $device->in_storage
    ? $device->update({snmp_ver => $info->snmp_ver})
    : $device->set_column(snmp_ver => $info->snmp_ver);

  if ($comm->{community}) {
      $device->in_storage
        ? $device->update({snmp_comm => $comm->{community}})
        : $device->set_column(snmp_comm => $comm->{community});
  }

  # regardless of device in storage, save the hint
  $device->update_or_create_related('community',
    {snmp_auth_tag_read => $comm->{tag}}) if $comm->{tag};

  return $info;
}

sub _try_write {
  my ($info, $device, $comm) = @_;

  my $loc = $info->load_location;
  $info->set_location($loc) or return undef;
  return undef unless ($loc eq $info->load_location);

  $device->in_storage
    ? $device->update({snmp_ver => $info->snmp_ver})
    : $device->set_column(snmp_ver => $info->snmp_ver);

  # one of these two cols must be set
  $device->update_or_create_related('community', {
    ($comm->{tag} ? (snmp_auth_tag_write => $comm->{tag}) : ()),
    ($comm->{community} ? (snmp_comm_rw => $comm->{community}) : ()),
  });

  return $info;
}

sub _mk_info_commargs {
  my $comm = shift;
  return () unless ref {} eq ref $comm and scalar keys %$comm;

  return (Community => $comm->{community})
    if exists $comm->{community};

  my $seclevel =
    (exists $comm->{auth} ?
    (exists $comm->{priv} ? 'authPriv' : 'authNoPriv' )
                          : 'noAuthNoPriv');

  return (
    SecName  => $comm->{user},
    SecLevel => $seclevel,
    ( exists $comm->{auth} ? (
      AuthProto => uc ($comm->{auth}->{proto} || 'MD5'),
      AuthPass  => ($comm->{auth}->{pass} || ''),
      ( exists $comm->{priv} ? (
        PrivProto => uc ($comm->{priv}->{proto} || 'DES'),
        PrivPass  => ($comm->{priv}->{pass} || ''),
      ) : ()),
    ) : ()),
  );
}

sub _build_mibdirs {
  my $home = (setting('mibhome') || dir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'netdisco-mibs'));
  return map { dir($home, $_)->stringify }
             @{ setting('mibdirs') || _get_mibdirs_content($home) };
}

sub _get_mibdirs_content {
  my $home = shift;
  my @list = map {s|$home/||; $_} grep {m/[a-z0-9]/} grep {-d} glob("$home/*");
  return \@list;
}

true;
