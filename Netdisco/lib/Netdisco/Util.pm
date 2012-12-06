package Netdisco::Util;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use NetAddr::IP::Lite;
use SNMP::Info;
use Config::Tiny;
use File::Slurp;
use Try::Tiny;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  load_nd_config
  is_discoverable
  is_vlan_interface port_has_phone
  get_device get_port get_iid
  vlan_reconfig_check port_reconfig_check
  snmp_connect
  sort_port
/;
our %EXPORT_TAGS = (port_control => [qw/
  get_device get_port snmp_connect
  port_reconfig_check
/]);

=head1 Netdisco::Util

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:port_control> tag will export the
C<get_device> and C<snmp_connect> subroutines.

=head2 is_discoverable( $ip )

Given an IP address, returns C<true> if Netdisco on this host is permitted to
discover its configuration by the local Netdisco configuration file.

The configuration items C<discover_no> and C<discover_only> are checked
against the given IP.

Returns false if the host is not permitted to discover the target device.

=cut

sub is_discoverable {
  my $ip = shift;

  my $device = NetAddr::IP::Lite->new($ip) or return 0;
  my $discover_no   = var('nd_config')->{_}->{discover_no};
  my $discover_only = var('nd_config')->{_}->{discover_only};

  if (length $discover_no) {
      my @d_no = split /,\s*/, $discover_no;
      foreach my $item (@d_no) {
          my $ip = NetAddr::IP::Lite->new($item) or return 0;
          return 0 if $ip->contains($device);
      }
  }

  if (length $discover_only) {
      my $okay = 0;
      my @d_only = split /,\s*/, $discover_only;
      foreach my $item (@d_only) {
          my $ip = NetAddr::IP::Lite->new($item) or return 0;
          ++$okay if $ip->contains($device);
      }
      return 0 if not $okay;
  }

  return 1;
}

=head2 load_nd_config( $filename )

Given the absolute file name of the Netdisco configuration, loads the
configuration from disk and returns it as a Hash reference.

All entries in the configuration appear under the "underscore" Hash key:

 my $config = load_nd_config('/etc/netdisco/netdisco.conf');
 say $config->{_}->{snmptimeout};

In addition, the configuration is saved into the Dancer I<vars> store under
the C<nd_config> key:

 say var('nd_config')->{_}->{snmptimeout};

Dies if it cannot load the configuration file.

=cut

sub load_nd_config {
  my $file = shift or die "missing netdisco config file name.\n";
  my $config = {};

  if (-e $file) {
      # read file and alter line continuations to be single lines
      my $config_content = read_file($file);
      $config_content =~ s/\\\n//sg;

      # parse config naively as .ini
      $config = Config::Tiny->new()->read_string($config_content);
      die (Config::Tiny->errstr ."\n") if !defined $config;
  }

  # store for later access
  var(nd_config => $config);

  return $config;
}

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

sub get_port {
  my ($device, $portname) = @_;

  # accept either ip or dbic object
  $device = get_device($device)
    if not ref $device;

  my $port = schema('Netdisco')->resultset('DevicePort')
    ->find({ip => $device->ip, port => $portname});

  return $port;
}

sub get_iid {
  my ($info, $port) = @_;

  # accept either port name or dbic object
  $port = $port->port if ref $port;

  my $interfaces = $info->interfaces;
  my %rev_if     = reverse %$interfaces;
  my $iid        = $rev_if{$port};

  return $iid;
}

sub is_vlan_interface {
  my $port = shift;

  my $is_vlan  = (($port->type and
    $port->type =~ /^(53|propVirtual|l2vlan|l3ipvlan|135|136|137)$/i)
    or ($port->port and $port->port =~ /vlan/i)
    or ($port->name and $port->name =~ /vlan/i)) ? 1 : 0;

  return $is_vlan;
}

sub port_has_phone {
  my $port = shift;

  my $has_phone = ($port->remote_type
    and $port->remote_type =~ /ip.phone/i) ? 1 : 0;

  return $has_phone;
}

sub vlan_reconfig_check {
  my $port = shift;
  my $ip = $port->ip;
  my $name = $port->port;
  my $nd_config = var('nd_config')->{_};

  my $is_vlan = is_vlan_interface($port);

  # vlan (routed) interface check
  return "forbidden: [$name] is a vlan interface on [$ip]"
    if $is_vlan;

  return "forbidden: not permitted to change native vlan"
    if not $nd_config->{vlanctl};

  return;
}

sub port_reconfig_check {
  my $port = shift;
  my $ip = $port->ip;
  my $name = $port->port;
  my $nd_config = var('nd_config')->{_};

  my $has_phone = has_phone($port);
  my $is_vlan   = is_vlan_interface($port);

  # uplink check
  return "forbidden: port [$name] on [$ip] is an uplink"
    if $port->remote_type and not $has_phone and not $nd_config->{allow_uplinks};

  # phone check
  return "forbidden: port [$name] on [$ip] is a phone"
    if $has_phone and $nd_config->{portctl_nophones};

  # vlan (routed) interface check
  return "forbidden: [$name] is a vlan interface on [$ip]"
    if $is_vlan and not $nd_config->{portctl_vlans};

  return;
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

=head2 sort_port( $a, $b )

Sort port names of various types used by device vendors. Interface is as
Perl's own C<sort> - two input args and an integer return value.

=cut

sub sort_port {
    my ($aval, $bval) = @_;

    # hack for foundry "10GigabitEthernet" -> cisco-like "TenGigabitEthernet"
    $aval = "Ten$1" if $aval =~ qr/^10(GigabitEthernet.+)$/;
    $bval = "Ten$1" if $bval =~ qr/^10(GigabitEthernet.+)$/;

    my $numbers        = qr{^(\d+)$};
    my $numeric        = qr{^([\d\.]+)$};
    my $dotted_numeric = qr{^(\d+)\.(\d+)$};
    my $letter_number  = qr{^([a-zA-Z]+)(\d+)$};
    my $wordcharword   = qr{^([^:\/.]+)[\ :\/\.]+([^:\/.]+)(\d+)?$}; #port-channel45
    my $netgear        = qr{^Slot: (\d+) Port: (\d+) }; # "Slot: 0 Port: 15 Gigabit - Level"
    my $ciscofast      = qr{^
                            # Word Number slash (Gigabit0/)
                            (\D+)(\d+)[\/:]
                            # Groups of symbol float (/5.5/5.5/5.5), separated by slash or colon
                            ([\/:\.\d]+)
                            # Optional dash (-Bearer Channel)
                            (-.*)?
                            $}x;

    my @a = (); my @b = ();

    if ($aval =~ $dotted_numeric) {
        @a = ($1,$2);
    } elsif ($aval =~ $letter_number) {
        @a = ($1,$2);
    } elsif ($aval =~ $netgear) {
        @a = ($1,$2);
    } elsif ($aval =~ $numbers) {
        @a = ($1);
    } elsif ($aval =~ $ciscofast) {
        @a = ($2,$1);
        push @a, split(/[:\/]/,$3), $4;
    } elsif ($aval =~ $wordcharword) {
        @a = ($1,$2,$3);
    } else {
        @a = ($aval);
    }

    if ($bval =~ $dotted_numeric) {
        @b = ($1,$2);
    } elsif ($bval =~ $letter_number) {
        @b = ($1,$2);
    } elsif ($bval =~ $netgear) {
        @b = ($1,$2);
    } elsif ($bval =~ $numbers) {
        @b = ($1);
    } elsif ($bval =~ $ciscofast) {
        @b = ($2,$1);
        push @b, split(/[:\/]/,$3),$4;
    } elsif ($bval =~ $wordcharword) {
        @b = ($1,$2,$3);
    } else {
        @b = ($bval);
    }

    # Equal until proven otherwise
    my $val = 0;
    while (scalar(@a) or scalar(@b)){
        # carried around from the last find.
        last if $val != 0;

        my $a1 = shift @a;
        my $b1 = shift @b;

        # A has more components - loses
        unless (defined $b1){
            $val = 1;
            last;
        }

        # A has less components - wins
        unless (defined $a1) {
            $val = -1;
            last;
        }

        if ($a1 =~ $numeric and $b1 =~ $numeric){
            $val = $a1 <=> $b1;
        } elsif ($a1 ne $b1) {
            $val = $a1 cmp $b1;
        }
    }

    return $val;
}

1;
