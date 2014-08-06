package App::Netdisco::Util::SNMP;

use Dancer qw/:syntax :script/;
use App::Netdisco::Util::Device qw/get_device check_device_no/;
use App::Netdisco::Util::Permission qw/check_acl/;

use SNMP::Info;
use Try::Tiny;
use Module::Load ();
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

sub snmp_connect { _snmp_connect_generic('read', @_) }

=head2 snmp_connect_rw( $ip )

Same as C<snmp_connect> but uses the read-write community string(s) from the
application configuration file.

Returns C<undef> if the connection fails.

=cut

sub snmp_connect_rw { _snmp_connect_generic('write', @_) }

sub _snmp_connect_generic {
  my ($mode, $ip, $useclass) = @_;
  $mode ||= 'read';

  # get device details from db
  my $device = get_device($ip);

  my %snmp_args = (
    AutoSpecify => 0,
    DestHost => $device->ip,
    Retries => (setting('snmpretries') || 2),
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

  # an override for bulkwalk
  $snmp_args{BulkWalk} = 0 if check_device_no($device, 'bulkwalk_no');

  # further protect against buggy Net-SNMP, and disable bulkwalk
  if ($snmp_args{BulkWalk}
      and ($SNMP::VERSION eq '5.0203' || $SNMP::VERSION eq '5.0301')) {

      warning sprintf
        "[%s] turning off BulkWalk due to buggy Net-SNMP - please upgrade!",
        $device->ip;
      $snmp_args{BulkWalk} = 0;
  }

  # get the community string(s)
  my @communities = _build_communities($device, $mode);

  # which SNMP versions to try and in what order
  my @versions =
    ( check_device_no($device->ip, 'snmpforce_v3') ? (3)
    : check_device_no($device->ip, 'snmpforce_v2') ? (2)
    : check_device_no($device->ip, 'snmpforce_v1') ? (1)
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
  my $debug_comm = ( $comm->{community}
      ? $ENV{SHOW_COMMUNITY} ? $comm->{community} : '<hidden>'
      : "v3user:$comm->{user}" );
  my $info = undef;

  try {
      debug
        sprintf '[%s] try_connect with ver: %s, class: %s, comm: %s',
        $snmp_args->{DestHost}, $snmp_args->{Version}, $class, $debug_comm;
      Module::Load::load $class;

      $info = $class->new(%$snmp_args, %comm_args);
      $info = ($mode eq 'read' ? _try_read($info, $device, $comm)
                               : _try_write($info, $device, $comm));

      # first time a device is discovered, re-instantiate into specific class
      if ($reclass and $info and $info->device_type ne $class) {
          $class = $info->device_type;
          debug
            sprintf '[%s] try_connect with ver: %s, new class: %s, comm: %s',
            $snmp_args->{DestHost}, $snmp_args->{Version}, $class, $debug_comm;

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
    {snmp_auth_tag => $comm->{tag}}) if $comm->{tag};

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
    ($comm->{tag} ? (snmp_auth_tag => $comm->{tag}) : ()),
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
  # warning 'Netdisco SNMP work will be slow - loading ALL MIBs. Consider setting mibdirs.';
  my @list = map {s|$home/||; $_} grep {-d} glob("$home/*");
  return \@list;
}

sub _build_communities {
  my ($device, $mode) = @_;
  $mode ||= 'read';

  my $config = (setting('snmp_auth') || []);
  my $stored_tag = eval { $device->community->snmp_auth_tag };
  my $snmp_comm_rw = eval { $device->community->snmp_comm_rw };
  my @communities = ();

  # try last-known-good read
  push @communities, {read => 1, community => $device->snmp_comm}
    if defined $device->snmp_comm and $mode eq 'read';

  # try last-known-good write
  push @communities, {write => 1, community => $snmp_comm_rw}
    if $snmp_comm_rw and $mode eq 'write';

  # new style snmp config
  foreach my $stanza (@$config) {
      # user tagged
      my $tag = '';
      if (1 == scalar keys %$stanza) {
          $tag = (keys %$stanza)[0];
          $stanza = $stanza->{$tag};

          # corner case: untagged lone community
          if ($tag eq 'community') {
              $tag = $stanza;
              $stanza = {community => $tag};
          }
      }

      # defaults
      $stanza->{tag} ||= $tag;
      $stanza->{read} = 1 if !exists $stanza->{read};
      $stanza->{only} ||= ['any'];
      $stanza->{only} = [$stanza->{only}] if ref '' eq ref $stanza->{only};

      die "error: config: snmpv3 stanza in snmp_auth must have a tag\n"
        if not $stanza->{tag}
           and !exists $stanza->{community};

      if ($stanza->{$mode} and check_acl($device->ip, $stanza->{only})) {
          if ($stored_tag and $stored_tag eq $stanza->{tag}) {
              # last known-good by tag
              unshift @communities, $stanza
          }
          else {
              push @communities, $stanza
          }
      }
  }

  # legacy config (note: read strings tried before write)
  if ($mode eq 'read') {
      push @communities, map {{
        read => 1,
        community => $_,
      }} @{setting('community') || []};
  }
  else {
      push @communities, map {{
        write => 1,
        community => $_,
      }} @{setting('community_rw') || []};
  }

  # but first of all, use external command if configured
  unshift @communities, _get_external_community($device, $mode)
    if setting('get_community') and length setting('get_community');

  return @communities;
}

sub _get_external_community {
  my ($device, $mode) = @_;
  my $cmd = setting('get_community');
  my $ip = $device->ip;
  my $host = $device->dns || $ip;

  if (defined $cmd and length $cmd) {
      # replace variables
      $cmd =~ s/\%HOST\%/$host/egi;
      $cmd =~ s/\%IP\%/$ip/egi;

      my $result = `$cmd`;
      return () unless defined $result and length $result;

      my @lines = split (m/\n/, $result);
      foreach my $line (@lines) {
          if ($line =~ m/^community\s*=\s*(.*)\s*$/i) {
              if (length $1 and $mode eq 'read') {
                  return map {{
                    read => 1,
                    community => $_,
                  }} split(m/\s*,\s*/,$1);
              }
          }
          elsif ($line =~ m/^setCommunity\s*=\s*(.*)\s*$/i) {
              if (length $1 and $mode eq 'write') {
                  return map {{
                    write => 1,
                    community => $_,
                  }} split(m/\s*,\s*/,$1);
              }
          }
      }
  }

  return ();
}

=head2 snmp_comm_reindex( $snmp, $device, $vlan )

Takes an established L<SNMP::Info> instance and makes a fresh connection using
community indexing, with the given C<$vlan> ID. Works for all SNMP versions.

=cut

sub snmp_comm_reindex {
  my ($snmp, $device, $vlan) = @_;
  my $ver = $snmp->snmp_ver;

  if ($ver == 3) {
      my $prefix = '';
      my @comms = _build_communities($device, 'read');
      foreach my $c (@comms) {
          next unless $c->{tag}
            and $c->{tag} eq (eval { $device->community->snmp_auth_tag } || '');
          $prefix = $c->{context_prefix} and last;
      }
      $prefix ||= 'vlan-';

      debug
        sprintf '[%s] reindexing to "%s%s" (ver: %s, class: %s)',
        $device->ip, $prefix, $vlan, $ver, $snmp->class;
      $snmp->update(Context => ($prefix . $vlan));
  }
  else {
      my $comm = $snmp->snmp_comm;

      debug sprintf '[%s] reindexing to vlan %s (ver: %s, class: %s)',
        $device->ip, $vlan, $ver, $snmp->class;
      $snmp->update(Community => $comm . '@' . $vlan);
  }
}

1;
