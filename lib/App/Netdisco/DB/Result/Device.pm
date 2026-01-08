use utf8;
package App::Netdisco::DB::Result::Device;

use strict;
use warnings;

use NetAddr::IP::Lite ':lower';
use App::Netdisco::Util::DNS 'hostname_from_ip';

use overload '""' => sub { shift->ip }, fallback => 1;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("device");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
  "dns",
  { data_type => "text", is_nullable => 1 },
  "description",
  { data_type => "text", is_nullable => 1 },
  "uptime",
  { data_type => "bigint", is_nullable => 1 },
  "contact",
  { data_type => "text", is_nullable => 1 },
  "name",
  { data_type => "text", is_nullable => 1 },
  "location",
  { data_type => "text", is_nullable => 1 },
  "layers",
  { data_type => "varchar", is_nullable => 1, size => 8 },
  "num_ports",
  { data_type => "integer", is_serializable => 0, is_nullable => 1 },
  "mac",
  { data_type => "macaddr", is_nullable => 1 },
  "serial",
  { data_type => "text", is_nullable => 1 },
  "chassis_id",
  { data_type => "text", is_nullable => 1 },
  "model",
  { data_type => "text", is_nullable => 1 },
  "ps1_type",
  { data_type => "text", is_nullable => 1 },
  "ps2_type",
  { data_type => "text", is_nullable => 1 },
  "ps1_status",
  { data_type => "text", is_nullable => 1 },
  "ps2_status",
  { data_type => "text", is_nullable => 1 },
  "fan",
  { data_type => "text", is_nullable => 1 },
  "slots",
  { data_type => "integer", is_nullable => 1 },
  "vendor",
  { data_type => "text", is_nullable => 1 },
  "os",
  { data_type => "text", is_nullable => 1 },
  "os_ver",
  { data_type => "text", is_nullable => 1 },
  "log",
  { data_type => "text", is_nullable => 1 },
  "snmp_ver",
  { data_type => "integer", is_nullable => 1 },
  "snmp_comm",
  { data_type => "text", is_nullable => 1 },
  "snmp_class",
  { data_type => "text", is_nullable => 1 },
  "snmp_engineid",
  { data_type => "text", is_nullable => 1 },
  "vtp_domain",
  { data_type => "text", is_nullable => 1 },
  "vtp_mode",
  { data_type => "text", is_nullable => 1 },
  "last_discover",
  { data_type => "timestamp", is_nullable => 1 },
  "last_macsuck",
  { data_type => "timestamp", is_nullable => 1 },
  "last_arpnip",
  { data_type => "timestamp", is_nullable => 1 },
  "is_pseudo",
  { data_type => "boolean", is_nullable => 0, default_value => \"false" },
  "pae_is_enabled",
  { data_type => "boolean", is_nullable => 1 },
  "custom_fields",
  { data_type => "jsonb", is_nullable => 0, default_value => \"{}" },
  "tags",
  { data_type => "text[]", is_nullable => 0, default_value => \"'{}'::text[]" },
);
__PACKAGE__->set_primary_key("ip");


=head1 RELATIONSHIPS

=head2 device_ips

Returns rows from the C<device_ip> table which relate to this Device. That is,
all the interface IP aliases configured on the Device.

=cut

__PACKAGE__->has_many( device_ips => 'App::Netdisco::DB::Result::DeviceIp', 'ip' );

=head2 device_ips_by_address_or_name

Returns rows from the C<device_ip> table which relate to this Device. That is,
all the interface IP aliases configured on the Device. However you probably
want to use the C<device_ips_with_address_or_name> ResultSet method instead,
so you can pass the MAC address part.

=cut

__PACKAGE__->has_many( device_ips_by_address_or_name => 'App::Netdisco::DB::Result::DeviceIp',
  sub {
    my $args = shift;
    return {
      "$args->{foreign_alias}.ip" => { -ident => "$args->{self_alias}.ip" },
      -or => [
        "$args->{foreign_alias}.dns" => { 'ilike', \'?' },
        "$args->{foreign_alias}.alias" => { '<<=', \'?' },
        "$args->{foreign_alias}.alias::text" => { 'ilike', \'?' },
      ],
    };
  },
  { cascade_copy => 0, cascade_update => 0, cascade_delete => 0 }
);

=head2 vlans

Returns the C<device_vlan> entries for this Device. That is, the list of VLANs
configured on or known by this Device.

=cut

__PACKAGE__->has_many( vlans => 'App::Netdisco::DB::Result::DeviceVlan', 'ip' );

=head2 ports

Returns the set of ports on this Device.

=cut

__PACKAGE__->has_many( ports => 'App::Netdisco::DB::Result::DevicePort', 'ip' );

=head2 ports_by_mac

Returns the set of ports on this Device, filtered by MAC. However you probably
want to use the C<ports_with_mac> ResultSet method instead, so you can pass the
MAC address part.

=cut

__PACKAGE__->has_many( ports_by_mac => 'App::Netdisco::DB::Result::DevicePort',
  sub {
    my $args = shift;
    return {
      "$args->{foreign_alias}.ip" => { -ident => "$args->{self_alias}.ip" },
      "$args->{foreign_alias}.mac::text" => { 'ilike', \'?' },
    };
  },
  { cascade_copy => 0, cascade_update => 0, cascade_delete => 0 }
);

=head2 module_serials

Returns the set chassis modules on this Device.

=cut

__PACKAGE__->has_many( module_serials => 'App::Netdisco::DB::Result::DeviceModule',
  sub {
    my $args = shift;
    return {
      "$args->{foreign_alias}.ip" => { -ident => "$args->{self_alias}.ip" },
      "$args->{foreign_alias}.class" => 'chassis',
      -and => [
        "$args->{foreign_alias}.serial" => { '!=' => undef },
        "$args->{foreign_alias}.serial" => { '!=' => '' },
      ],
    };
  },
  { cascade_copy => 0, cascade_update => 0, cascade_delete => 0 }
);

=head2 modules

Returns the set chassis modules on this Device.

=cut

__PACKAGE__->has_many( modules => 'App::Netdisco::DB::Result::DeviceModule', 'ip' );

=head2 power_modules

Returns the set of power modules on this Device.

=cut

__PACKAGE__->has_many( power_modules => 'App::Netdisco::DB::Result::DevicePower', 'ip' );

=head2 oids

Returns the oids walked on this Device.

=cut

__PACKAGE__->has_many( oids => 'App::Netdisco::DB::Result::DeviceBrowser', 'ip' );

=head2 port_vlans

Returns the set of VLANs known to be configured on Ports on this Device,
either tagged or untagged.

The JOIN is of type "RIGHT" meaning that the results are constrained to VLANs
only on Ports on this Device.

=cut

__PACKAGE__->has_many(
    port_vlans => 'App::Netdisco::DB::Result::DevicePortVlan',
    'ip', { join_type => 'RIGHT' }
);

=head2 port_vlans_filter

A JOIN condition which can be used to filter a set of Devices to those known
carrying a given VLAN on its ports. Uses an INNER JOIN to achieve this.

=cut

__PACKAGE__->has_many(
    port_vlans_filter => 'App::Netdisco::DB::Result::DevicePortVlan',
    'ip', { join_type => 'INNER' }
);

# helper which assumes we've just RIGHT JOINed to Vlans table
sub vlan { return (shift)->vlans->first }

=head2 wireless_ports

Returns the set of wireless IDs known to be configured on Ports on this
Device.

=cut

__PACKAGE__->has_many(
    wireless_ports => 'App::Netdisco::DB::Result::DevicePortWireless',
    'ip', { join_type => 'RIGHT' }
);

=head2 ssids

Returns the set of SSIDs known to be configured on Ports on this Device.

=cut

__PACKAGE__->has_many(
    ssids => 'App::Netdisco::DB::Result::DevicePortSsid',
    'ip', { join_type => 'RIGHT' }
);

=head2 properties_ports

Returns the set of ports known to have recorded properties

=cut

__PACKAGE__->has_many(
    properties_ports => 'App::Netdisco::DB::Result::DevicePortProperties',
    'ip', { join_type => 'RIGHT' }
);

=head2 powered_ports

Returns the set of ports known to have PoE capability

=cut

__PACKAGE__->has_many(
    powered_ports => 'App::Netdisco::DB::Result::DevicePortPower',
    'ip', { join_type => 'RIGHT' }
);

=head2 community

Returns the row from the community string table, if one exists.

=cut

__PACKAGE__->might_have(
    community => 'App::Netdisco::DB::Result::Community', 'ip');

=head2 throughput

Returns a sum of speeds on all ports on the device.

=cut

__PACKAGE__->has_one(
    throughput => 'App::Netdisco::DB::Result::Virtual::DevicePortSpeed', 'ip');

=head1 ADDITIONAL METHODS

=head2 has_layer( $number )

Returns true if the device provided sysServices and supports the given layer.

=cut

sub has_layer {
  my ($device, $layer) = @_;
  return unless $layer and $layer =~ m/^[1-7]$/;
  return ($device->layers and (substr($device->layers, (8-$layer), 1) == 1));
}

=head2 renumber( $new_ip )

Will update this device and all related database records to use the new IP
C<$new_ip>. Returns C<undef> if $new_ip seems invalid, otherwise returns the
Device row object.

=cut

sub renumber {
  my ($device, $ip) = @_;
  my $schema = $device->result_source->schema;

  my $new_addr = NetAddr::IP::Lite->new($ip)
    or return;

  my $old_ip = $device->ip;
  my $new_ip = $new_addr->addr;

  return if $new_ip eq '0.0.0.0';

  # the special record in device_ip which is always there
  $schema->resultset('DeviceIp')
    ->search({ip => $old_ip, alias => $old_ip})
    ->update({ip => $new_ip, alias => $new_ip});
  $schema->resultset('DeviceIp')
    ->search({ip => $old_ip, alias => $new_ip})->delete();

  # Community is not included as SNMP::test_connection will take care of it
  foreach my $set (qw/
    DeviceBrowser
    DeviceIp
    DeviceModule
    DevicePower
    DeviceVlan
    DevicePort
    DevicePortLog
    DevicePortPower
    DevicePortProperties
    DevicePortSsid
    DevicePortVlan
    DevicePortWireless
  /) {
    $schema->resultset($set)
      ->search({ip => $old_ip})
      ->update({ip => $new_ip});
  }

  $schema->resultset('DeviceSkip')
    ->search({device => $new_ip})->delete;
  $schema->resultset('DeviceSkip')
    ->search({device => $old_ip})
    ->update({device => $new_ip});

  $schema->resultset('DevicePort')
    ->search({remote_ip => $old_ip})
    ->update({remote_ip => $new_ip});

  $schema->resultset('Node')
    ->search({switch => $old_ip})
    ->update({switch => $new_ip});

  # this whole shenanigans exists because I cannot work out how to
  # pass an escaped SQL placeholder into DBIx::Class/SQL::Abstract
  # see https://www.mail-archive.com/dbix-class@lists.scsys.co.uk/msg07079.html
  $schema->storage->dbh_do(sub {
    my ($storage, $dbh, @extra) = @_;
    local $dbh->{TraceLevel} = ($ENV{DBIC_TRACE} ? '1|SQL' : $dbh->{TraceLevel});

    my $router_first_sql = q{
      UPDATE node_ip
        SET seen_on_router_first = seen_on_router_first - ?::text || jsonb_build_object(?::text, seen_on_router_first -> ?::text)
        WHERE seen_on_router_first \? ?::text
    };
    $dbh->do($router_first_sql, undef, $old_ip, $new_ip, $old_ip, $old_ip);

    my $router_last_sql = q{
      UPDATE node_ip
        SET seen_on_router_last = seen_on_router_last - ?::text || jsonb_build_object(?::text, seen_on_router_last -> ?::text)
        WHERE seen_on_router_last \? ?::text
    };
    $dbh->do($router_last_sql, undef, $old_ip, $new_ip, $old_ip, $old_ip);
  });

  $schema->resultset('Topology')
    ->search({dev1 => $old_ip})
    ->update({dev1 => $new_ip});

  $schema->resultset('Topology')
    ->search({dev2 => $old_ip})
    ->update({dev2 => $new_ip});

  $schema->resultset('Admin')->search({
    device => $old_ip,
  })->delete;

  $device->update({
    ip  => $new_ip,
    dns => (hostname_from_ip($new_ip)
      || eval { $schema->resultset('DeviceIp')->find($new_ip,$new_ip)->dns } || undef),
  });

  return $device;
}

=head1 ADDITIONAL COLUMNS

=head2 port_count

Returns the number of ports on this device. Enable this
column by applying the C<with_port_count()> modifier to C<search()>.

=cut

sub port_count { return (shift)->get_column('port_count') }

=head2 is_discoverable

Returns the number of backends able to discover the device. Enable this
column by applying the C<with_layer_features()> modifier to C<search()>.

=cut

sub is_discoverable { return (shift)->get_column('is_discoverable') }

=head2 is_macsuckable

Returns the number of backends able to macsuck the device. Enable this
column by applying the C<with_layer_features()> modifier to C<search()>.

=cut

sub is_macsuckable { return (shift)->get_column('is_macsuckable') }

=head2 is_arpnipable

Returns the number of backends able to arpnip the device. Enable this
column by applying the C<with_layer_features()> modifier to C<search()>.

=cut

sub is_arpnipable { return (shift)->get_column('is_arpnipable') }

=head2 uptime_age

Formatted version of the C<uptime> field.

The format is in "X days/months/years" style, similar to:

 1 year 4 months 05:46:00

=cut

sub uptime_age  { return (shift)->get_column('uptime_age')  }

=head2 first_seen_stamp

Formatted version of the C<creation> field, accurate to the minute.

The format is somewhat like ISO 8601 or RFC3339 but without the middle C<T>
between the date stamp and time stamp. That is:

 2012-02-06 12:49

=cut

sub first_seen_stamp  { return (shift)->get_column('first_seen_stamp')  }

=head2 last_discover_stamp

Formatted version of the C<last_discover> field, accurate to the minute.

The format is somewhat like ISO 8601 or RFC3339 but without the middle C<T>
between the date stamp and time stamp. That is:

 2012-02-06 12:49

=cut

sub last_discover_stamp  { return (shift)->get_column('last_discover_stamp')  }

=head2 last_macsuck_stamp

Formatted version of the C<last_macsuck> field, accurate to the minute.

The format is somewhat like ISO 8601 or RFC3339 but without the middle C<T>
between the date stamp and time stamp. That is:

 2012-02-06 12:49

=cut

sub last_macsuck_stamp  { return (shift)->get_column('last_macsuck_stamp')  }

=head2 last_arpnip_stamp

Formatted version of the C<last_arpnip> field, accurate to the minute.

The format is somewhat like ISO 8601 or RFC3339 but without the middle C<T>
between the date stamp and time stamp. That is:

 2012-02-06 12:49

=cut

sub last_arpnip_stamp  { return (shift)->get_column('last_arpnip_stamp')  }

=head2 since_last_discover

Number of seconds which have elapsed since the value of C<last_discover>.

=cut

sub since_last_discover  { return (shift)->get_column('since_last_discover')  }

=head2 since_last_macsuck

Number of seconds which have elapsed since the value of C<last_macsuck>.

=cut

sub since_last_macsuck  { return (shift)->get_column('since_last_macsuck')  }

=head2 since_last_arpnip

Number of seconds which have elapsed since the value of C<last_arpnip>.

=cut

sub since_last_arpnip  { return (shift)->get_column('since_last_arpnip')  }

1;
