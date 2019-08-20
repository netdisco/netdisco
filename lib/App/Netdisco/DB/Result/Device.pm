use utf8;
package App::Netdisco::DB::Result::Device;


use strict;
use warnings;

use NetAddr::IP::Lite ':lower';
use App::Netdisco::Util::DNS 'hostname_from_ip';

use overload '""' => sub { shift->ip }, fallback => 1;

use base 'DBIx::Class::Core';
__PACKAGE__->table("device");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
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
  "ports",
  { data_type => "integer", is_nullable => 1 },
  "mac",
  { data_type => "macaddr", is_nullable => 1 },
  "serial",
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
  "vtp_domain",
  { data_type => "text", is_nullable => 1 },
  "last_discover",
  { data_type => "timestamp", is_nullable => 1 },
  "last_macsuck",
  { data_type => "timestamp", is_nullable => 1 },
  "last_arpnip",
  { data_type => "timestamp", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("ip");


=head1 RELATIONSHIPS

=head2 device_ips

Returns rows from the C<device_ip> table which relate to this Device. That is,
all the interface IP aliases configured on the Device.

=cut

__PACKAGE__->has_many( device_ips => 'App::Netdisco::DB::Result::DeviceIp', 'ip' );

=head2 vlans

Returns the C<device_vlan> entries for this Device. That is, the list of VLANs
configured on or known by this Device.

=cut

__PACKAGE__->has_many( vlans => 'App::Netdisco::DB::Result::DeviceVlan', 'ip' );

=head2 ports

Returns the set of ports on this Device.

=cut

__PACKAGE__->has_many( ports => 'App::Netdisco::DB::Result::DevicePort', 'ip' );

=head2 modules

Returns the set chassis modules on this Device.

=cut

__PACKAGE__->has_many( modules => 'App::Netdisco::DB::Result::DeviceModule', 'ip' );

=head2 power_modules

Returns the set of power modules on this Device.

=cut

__PACKAGE__->has_many( power_modules => 'App::Netdisco::DB::Result::DevicePower', 'ip' );

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

=head2 is_pseudo

Returns true if the vendor of the device is "netdisco".

=cut

sub is_pseudo {
  my $device = shift;
  return (defined $device->vendor and $device->vendor eq 'netdisco');
}

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

  return
    if $new_ip eq '0.0.0.0'
    or $new_ip eq '127.0.0.1';

  # Community is not included as SNMP::test_connection will take care of it
  foreach my $set (qw/
    DeviceIp
    DeviceModule
    DevicePort
    DevicePortLog
    DevicePortPower
    DevicePortProperties
    DevicePortSsid
    DevicePortVlan
    DevicePortWireless
    DevicePower
    DeviceVlan
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

  $schema->resultset('Topology')
    ->search({dev1 => $old_ip})
    ->update({dev1 => $new_ip});

  $schema->resultset('Topology')
    ->search({dev2 => $old_ip})
    ->update({dev2 => $new_ip});

  $device->update({
    ip  => $new_ip,
    dns => hostname_from_ip($new_ip),
  });

  return $device;
}

=head1 ADDITIONAL COLUMNS

=head2 oui

Returns the first half of the device MAC address.

=cut

sub oui { return substr( ((shift)->mac || ''), 0, 8 ) }

=head2 port_count

Returns the number of ports on this device. Enable this
column by applying the C<with_port_count()> modifier to C<search()>.

=cut

sub port_count { return (shift)->get_column('port_count') }


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
