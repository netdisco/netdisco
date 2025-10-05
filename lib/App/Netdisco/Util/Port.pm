package App::Netdisco::Util::Port;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::Device 'get_device';
use App::Netdisco::Util::Permission qw/acl_matches acl_matches_only/;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  port_acl_by_role_check port_acl_check
  port_acl_service port_acl_pvid port_acl_name
  get_port get_iid get_powerid
  database_port_acl_by_role_check
  is_vlan_subinterface port_has_phone port_has_wap
  to_speed
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::Port

=head1 DESCRIPTION

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 database_port_acl_by_role_check( $port, $device, $user_or_role, $what_to_check? )

=over 4

=item *

Permission check on C<portctl_by_role> if the device and user are provided. This
checks for ACLs defined in the database. Either a bare username or a role name
can be supplied.

=back

Will return false if these checks fail, otherwise true.

=cut

sub database_port_acl_by_role_check {
  my ($port, $device, $user) = @_;
  my $role = $user->portctl_role;

  my $device_acl = schema(vars->{'tenant'})->resultset('PortctlRoleDevice')
    ->search({ role_name => $role, device_ip => $device->ip })
    ->single;

  if ($device_acl){
    return false unless $device_acl;
  }

  my @portctl_acl = schema(vars->{'tenant'})->resultset('PortctlRoleDevicePort')
    ->search({ role_name => $role, device_ip => $device->ip })
    ->all;

  return true unless @portctl_acl; # no acl for this device's ports, all ports permitted

  my @acl = map { $_->acl } @portctl_acl;
  return acl_matches($port, \@acl);
}

=head2 config_port_acl_by_role_check( $port, $device?, $user? )

=over 4

=item *

Permission check on C<portctl_by_role> if the device and user are provided. A
bare username will be promoted to a user instance.

=back

Will return false if these checks fail, otherwise true.

=cut

sub config_port_acl_by_role_check {
  my ($port, $device, $user) = @_;
  my $role = $user->portctl_role;

  my $acl  = $role ? setting('portctl_by_role')->{$role} : undef;

  if ($acl and (ref $acl eq q{} or ref $acl eq ref [])) {
      # all ports are permitted when the role acl is a device acl
      # but check the device anyway
      return true if acl_matches($device, $acl);
  }
  elsif ($acl and ref $acl eq ref {}) {
      my $found = false;
      foreach my $key (sort keys %$acl) {
          # lhs matches device, rhs matches port
          next unless $key and $acl->{$key};
          if (acl_matches($device, $key)
              and acl_matches($port, $acl->{$key})) {

              $found = true;
              last;
          }
      }

      return true if $found;
  }
  elsif ($role) {
      # the config does not have an entry for user's role
      return true if $user->port_control;
  }

  # the user has "Enabled (any port)" setting
  return $user->port_control;
}

=head2 port_acl_by_role_check( $port, $device?, $user? )

=over 4

=item *

Permission check on C<portctl_by_role> if the device and user are provided. A
bare username will be promoted to a user instance.

=back

Will return false if these checks fail, otherwise true.

=cut

sub port_acl_by_role_check {
  my ($port, $device, $user) = @_;
  # skip user acls for netdisco-do --force jobs
  # this avoids the need to create a netdisco user in the DB and give rights
  return true if $ENV{ND2_DO_FORCE};

  if ($device and ref $device and $user) {
    $user = ref $user ? $user :
      schema('netdisco')->resultset('User')
                        ->find({ username => $user });

    return false unless $user;
    my $username = $user->username;

    # special case admin user allowed to continue, because
    # they can submit port control jobs
    return true if ($user->admin and $user->port_control);


    my $portctl_mode = setting('portctl_mode');

    if ($portctl_mode eq 'hybrid'){
      return (database_port_acl_by_role_check($port, $device, $user) || config_port_acl_by_role_check($port, $device, $user));
    }
    elsif ($portctl_mode eq 'database') {
      return database_port_acl_by_role_check($port, $device, $user);
    } # use ACLs defined in DB
    else {
      return config_port_acl_by_role_check($port, $device, $user);
    } # use ACLs defined in deployment.yml
  }
  return false;
}

=head2 port_acl_check( $port, $device?, $user? )

=over 4

=item *

Permission check that C<portctl_no> and C<portctl_only> pass for the device.

=back

Will return false if these checks fail, otherwise true.

=cut

sub port_acl_check {
  my ($port, $device, $user) = @_;
  my $ip = $port->ip;

  # check for limits on devices
  return false if acl_matches($ip, 'portctl_no');
  return false unless acl_matches_only($ip, 'portctl_only');

  return true;
}

=head2 port_acl_service( $port, $device?, $user? )

Checks if admin up/down or PoE status on a port can be changed.

Returns false if the request should be denied, true if OK to proceed.

First checks C<portctl_nameonly>, C<portctl_uplinks>, C<portctl_nowaps>, and
C<portctl_nophones>.

Then checks according to C<port_acl_check> and C<port_acl_by_role_check> above.

=cut

sub port_acl_service {
  my ($port, $device, $user) = @_;

  return false if setting('portctl_nameonly');

  return false if setting('portctl_nowaps') and port_has_wap($port);
  return false if setting('portctl_nophones') and port_has_phone($port);

  return false if (not setting('portctl_uplinks')) and
    (($port->is_uplink or $port->remote_type
      or $port->is_master or is_vlan_subinterface($port))and not
     (port_has_wap($port) or port_has_phone($port)));

  return false if not port_acl_check(@_);
  return port_acl_by_role_check(@_);
}

=head2 port_acl_pvid( $port, $device?, $user? )

Checks if native vlan (pvid) on a port can be changed.

Returns false if the request should be denied, true if OK to proceed.

First checks C<portctl_native_vlan>;

Then checks according to C<port_acl_service>.

=cut

sub port_acl_pvid {
  my ($port, $device, $user) = @_;

  return false unless setting('portctl_native_vlan');
  return port_acl_service(@_);
}

=head2 port_acl_name( $port, $device?, $user? )

Checks if name (description) on a port can be changed.

Returns false if the request should be denied, true if OK to proceed.

Only setting C<portctl_by_role> is checked.

=cut

sub port_acl_name { goto &port_acl_by_role_check }

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

=head2 get_port( $device, $portname )

Given a device IP address and a port name, returns a L<DBIx::Class::Row>
object for the Port on the Device in the Netdisco database.

The device IP can also be passed as a Device C<DBIx::Class> object.

Returns C<undef> if the device or port are not known to Netdisco.

Returns C<($device_instance, $port_instance)> in list context, otherwise just
C<$port_instance>.

=cut

sub get_port {
  my ($device, $portname) = @_;

  # accept either ip or dbic object
  $device = get_device($device);

  return unless $device and $device->in_storage;

  my $port = schema(vars->{'tenant'})->resultset('DevicePort')->with_properties
    ->find({ip => $device->ip, port => $portname});

  return unless $port and $port->in_storage;

  return ( wantarray ? ($device, $port) : $port );
}

=head2 get_iid( $info, $port )

Given an L<SNMP::Info> instance for a device, and the name of a port, returns
the current interface table index for that port. This can be used in further
SNMP requests on attributes of the port.

Returns C<undef> if there is no such port name on the device.

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

=head2 get_powerid( $info, $port )

Given an L<SNMP::Info> instance for a device, and the name of a port, returns
the current PoE table index for the port. This can be used in further SNMP
requests on PoE attributes of the port.

Returns C<undef> if there is no such port name on the device.

=cut

sub get_powerid {
  my ($info, $port) = @_;

  # accept either port name or dbic object
  $port = $port->port if ref $port;

  my $iid = get_iid($info, $port)
    or return undef;

  my $p_interfaces = $info->peth_port_ifindex;
  my %rev_p_if     = reverse %$p_interfaces;
  my $powerid      = $rev_p_if{$iid};

  return $powerid;
}

=head2 is_vlan_subinterface( $port )

Returns true if the C<$port> L<DBIx::Class> object represents a vlan
subinterface or is the logical parent of such a port.

This uses simple checks on the port I<type> and I<descr>, and therefore might
sometimes returns a false-negative result.

=cut

sub is_vlan_subinterface {
  my $port = shift;
  return true if $port->has_subinterfaces;

  my $is_vlan  = (($port->type and
    $port->type =~ /^(53|propVirtual|l2vlan|l3ipvlan|135|136|137)$/i)
    or ($port->port and $port->port =~ /vlan/i)
    or ($port->descr and $port->descr =~ /vlan/i)) ? 1 : 0;

  return $is_vlan;
}

=head2 port_has_phone( $port )

Returns true if the C<$port> L<DBIx::Class> object has a phone connected.

=cut

sub port_has_phone {
  my $row = shift;
  return $row->remote_is_phone if $row->can('remote_is_phone');
  my $properties = $row->properties;
  return ($properties ? $properties->remote_is_phone : undef);
}

=head2 port_has_wap( $port )

Returns true if the C<$port> L<DBIx::Class> object has a wireless AP  connected.

=cut

sub port_has_wap {
  my $row = shift;
  return $row->remote_is_wap if $row->can('remote_is_wap');
  my $properties = $row->properties;
  return ($properties ? $properties->remote_is_wap : undef);
}

# copied from SNMP::Info to avoid introducing dependency to web frontend
sub munge_highspeed {
    my $speed = shift;
    my $fmt   = "%d Mbps";

    if ( $speed > 9999999 ) {
        $fmt = "%d Tbps";
        $speed /= 1000000;
    }
    elsif ( $speed > 999999 ) {
        $fmt = "%.1f Tbps";
        $speed /= 1000000.0;
    }
    elsif ( $speed > 9999 ) {
        $fmt = "%d Gbps";
        $speed /= 1000;
    }
    elsif ( $speed > 999 ) {
        $fmt = "%.1f Gbps";
        $speed /= 1000.0;
    }
    return sprintf( $fmt, $speed );
}

=head2 to_speed( $speed )

Incorporate SNMP::Info C<munge_highspeed> to avoid extra dependency on web frontend.

=cut

sub to_speed {
  my $speed = shift or return '';
  return $speed if $speed =~ m/\D/;
  ($speed = munge_highspeed($speed / 1_000_000)) =~ s/\.0 ?//g;
  return $speed;
}

1;
