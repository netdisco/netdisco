use utf8;
package App::Netdisco::DB::Result::Device;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

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


# Created by DBIx::Class::Schema::Loader v0.07015 @ 2012-01-07 14:20:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:671/XuuvsO2aMB1+IRWFjg

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

=head1 ADDITIONAL COLUMNS

=head2 uptime_age

Formatted version of the C<uptime> field.

The format is in "X days/months/years" style, similar to:

 1 year 4 months 05:46:00

=cut

sub uptime_age  { return (shift)->get_column('uptime_age')  }

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

1;
