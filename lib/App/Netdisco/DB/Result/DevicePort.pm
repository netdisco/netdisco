use utf8;
package App::Netdisco::DB::Result::DevicePort;


use strict;
use warnings;

use NetAddr::MAC;

use MIME::Base64 'encode_base64url';

use base 'DBIx::Class::Core';
__PACKAGE__->table("device_port");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "port",
  { data_type => "text", is_nullable => 0 },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
  "descr",
  { data_type => "text", is_nullable => 1 },
  "up",
  { data_type => "text", is_nullable => 1 },
  "up_admin",
  { data_type => "text", is_nullable => 1 },
  "type",
  { data_type => "text", is_nullable => 1 },
  "duplex",
  { data_type => "text", is_nullable => 1 },
  "duplex_admin",
  { data_type => "text", is_nullable => 1 },
  "speed",
  { data_type => "text", is_nullable => 1 },
  "name",
  { data_type => "text", is_nullable => 1 },
  "mac",
  { data_type => "macaddr", is_nullable => 1 },
  "mtu",
  { data_type => "integer", is_nullable => 1 },
  "stp",
  { data_type => "text", is_nullable => 1 },
  "remote_ip",
  { data_type => "inet", is_nullable => 1 },
  "remote_port",
  { data_type => "text", is_nullable => 1 },
  "remote_type",
  { data_type => "text", is_nullable => 1 },
  "remote_id",
  { data_type => "text", is_nullable => 1 },
  "is_master",
  { data_type => "boolean", is_nullable => 0, default_value => \"false" },
  "slave_of",
  { data_type => "text", is_nullable => 1 },
  "manual_topo",
  { data_type => "boolean", is_nullable => 0, default_value => \"false" },
  "is_uplink",
  { data_type => "boolean", is_nullable => 1 },
  "vlan",
  { data_type => "text", is_nullable => 1 },
  "pvid",
  { data_type => "integer", is_nullable => 1 },
  "lastchange",
  { data_type => "bigint", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("port", "ip");



=head1 RELATIONSHIPS

=head2 device

Returns the Device table entry to which the given Port is related.

=cut

__PACKAGE__->belongs_to( device => 'App::Netdisco::DB::Result::Device', 'ip' );

=head2 port_vlans

Returns the set of C<device_port_vlan> entries associated with this Port.
These will be both tagged and untagged. Use this relation in search conditions.

=cut

__PACKAGE__->has_many( port_vlans => 'App::Netdisco::DB::Result::DevicePortVlan',
  { 'foreign.ip' => 'self.ip', 'foreign.port' => 'self.port' } );

=head2 nodes / active_nodes / nodes_with_age / active_nodes_with_age

Returns the set of Nodes whose MAC addresses are associated with this Device
Port.

The C<active> variants return only the subset of nodes currently in the switch
MAC address table, that is the active ones.

The C<with_age> variants add an additional column C<time_last_age>, a
preformatted value for the Node's C<time_last> field, which reads as "X
days/weeks/months/years".

=cut

__PACKAGE__->has_many( nodes => 'App::Netdisco::DB::Result::Node',
  {
    'foreign.switch' => 'self.ip',
    'foreign.port' => 'self.port',
  },
  { join_type => 'LEFT' },
);

__PACKAGE__->has_many( nodes_with_age => 'App::Netdisco::DB::Result::Virtual::NodeWithAge',
  {
    'foreign.switch' => 'self.ip',
    'foreign.port' => 'self.port',
  },
  { join_type => 'LEFT',
    cascade_copy => 0, cascade_update => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many( active_nodes => 'App::Netdisco::DB::Result::Virtual::ActiveNode',
  {
    'foreign.switch' => 'self.ip',
    'foreign.port' => 'self.port',
  },
  { join_type => 'LEFT',
    cascade_copy => 0, cascade_update => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many( active_nodes_with_age => 'App::Netdisco::DB::Result::Virtual::ActiveNodeWithAge',
  {
    'foreign.switch' => 'self.ip',
    'foreign.port' => 'self.port',
  },
  { join_type => 'LEFT',
    cascade_copy => 0, cascade_update => 0, cascade_delete => 0 },
);

=head2 logs

Returns the set of C<device_port_log> entries associated with this Port.

=cut

__PACKAGE__->has_many( logs => 'App::Netdisco::DB::Result::DevicePortLog',
  { 'foreign.ip' => 'self.ip', 'foreign.port' => 'self.port' },
);

=head2 power

Returns a row from the C<device_port_power> table if one refers to this
device port.

=cut

__PACKAGE__->might_have( power => 'App::Netdisco::DB::Result::DevicePortPower', {
  'foreign.ip' => 'self.ip', 'foreign.port' => 'self.port',
});

=head2 properties

Returns a row from the C<device_port_properties> table if one refers to this
device port.

=cut

__PACKAGE__->might_have( properties => 'App::Netdisco::DB::Result::DevicePortProperties', {
  'foreign.ip' => 'self.ip', 'foreign.port' => 'self.port',
});

=head2 ssid

Returns a row from the C<device_port_ssid> table if one refers to this
device port.

=cut

__PACKAGE__->might_have(
    ssid => 'App::Netdisco::DB::Result::DevicePortSsid',
    {   'foreign.ip'   => 'self.ip',
        'foreign.port' => 'self.port',
    }
);

=head2 wireless

Returns a row from the C<device_port_wireless> table if one refers to this
device port.

=cut

__PACKAGE__->might_have(
    wireless => 'App::Netdisco::DB::Result::DevicePortWireless',
    {   'foreign.ip'   => 'self.ip',
        'foreign.port' => 'self.port',
    }
);

=head2 agg_master

Returns another row from the C<device_port> table if this port is slave
to another in a link aggregate.

=cut

__PACKAGE__->belongs_to(
    agg_master => 'App::Netdisco::DB::Result::DevicePort', {
      'foreign.ip'   => 'self.ip',
      'foreign.port' => 'self.slave_of',
    }, {
      join_type => 'LEFT',
    }
);

=head2 neighbor_alias

When a device port has an attached neighbor device, this relationship will
return the IP address of the neighbor. See the C<neighbor> helper method if
what you really want is to retrieve the Device entry for that neighbor.

The JOIN is of type "LEFT" in case the neighbor device is known but has not
been fully discovered by Netdisco and so does not exist itself in the
database.

=cut

__PACKAGE__->belongs_to( neighbor_alias => 'App::Netdisco::DB::Result::DeviceIp',
  sub {
      my $args = shift;
      return {
          "$args->{foreign_alias}.alias" => { '=' =>
            $args->{self_resultsource}->schema->resultset('DeviceIp')
              ->search({alias => { -ident => "$args->{self_alias}.remote_ip"}},
                       {rows => 1, columns => 'ip', alias => 'devipsub'})->as_query }
      };
  },
  { join_type => 'LEFT' },
);

=head2 vlans

As compared to C<port_vlans>, this relationship returns a set of Device VLAN
row objects for the VLANs on the given port, which might be more useful if you
want to find out details such as the VLAN name.

See also C<vlan_count>.

=cut

__PACKAGE__->many_to_many( vlans => 'port_vlans', 'vlan' );


=head2 oui

Returns the C<oui> table entry matching this Port. You can then join on this
relation and retrieve the Company name from the related table.

The JOIN is of type LEFT, in case the OUI table has not been populated.

=cut

__PACKAGE__->belongs_to( oui => 'App::Netdisco::DB::Result::Oui',
  sub {
      my $args = shift;
      return {
          "$args->{foreign_alias}.oui" =>
            { '=' => \"substring(cast($args->{self_alias}.mac as varchar) for 8)" }
      };
  },
  { join_type => 'LEFT' }
);

=head1 ADDITIONAL METHODS

=head2 neighbor

Returns the Device entry for the neighbour Device on the given port.

Might return an undefined value if there is no neighbor on the port, or if the
neighbor has not been fully discovered by Netdisco and so does not exist in
the database.

=cut

sub neighbor {
    my $row = shift;
    return eval { $row->neighbor_alias->device || undef };
}

=head1 ADDITIONAL COLUMNS

=head2 native

An alias for the C<vlan> column, which stores the PVID (that is, the VLAN
ID assigned to untagged frames received on the port).

=cut

sub native { return (shift)->vlan }

=head2 error_disable_cause

Returns the textual reason given by the device if the port is in an error
state, or else `undef` if the port is not in an error state.

=cut

sub error_disable_cause { return (shift)->get_column('error_disable_cause') }

=head2 remote_is_wap

Returns true if the remote LLDP neighbor has reported Wireless Access Point
capability.

=cut

sub remote_is_wap { return (shift)->get_column('remote_is_wap') }

=head2 remote_is_phone

Returns true if the remote LLDP neighbor has reported Telephone capability.

=cut

sub remote_is_phone { return (shift)->get_column('remote_is_phone') }

=head2 remote_inventory

Returns a synthesized description of the remote LLDP device if inventory
information was given, including vendor, model, OS version, and serial number.

=cut

sub remote_inventory {
  my $port = shift;
  my $os_ver = ($port->get_column('remote_os_ver')
    ? ('running '. $port->get_column('remote_os_ver')) : '');
  my $serial = ($port->get_column('remote_serial')
    ? ('('. $port->get_column('remote_serial') .')') : '');

  my $retval = join ' ', ($port->get_column('remote_vendor') || ''),
    ($port->get_column('remote_model') || ''), $serial, $os_ver;

  return (($retval =~ m/[[:alnum:]]/) ? $retval : '');
}

=head2 vlan_count

Returns the number of VLANs active on this device port. Enable this column by
applying the C<with_vlan_count()> modifier to C<search()>.

=cut

sub vlan_count { return (shift)->get_column('vlan_count') }

=head2 lastchange_stamp

Formatted version of the C<lastchange> field, accurate to the minute. Enable
this column by applying the C<with_times()> modifier to C<search()>.

The format is somewhat like ISO 8601 or RFC3339 but without the middle C<T>
between the date stamp and time stamp. That is:

 2012-02-06 12:49

=cut

sub lastchange_stamp { return (shift)->get_column('lastchange_stamp') }

=head2 is_free

This method can be used to evaluate whether a device port could be considered
unused, based on the last time it changed from the "up" state to a "down"
state.

See the C<with_is_free> and C<only_free_ports> modifiers to C<search()>.

=cut

sub is_free { return (shift)->get_column('is_free') }

=head2 base64url_port

Returns a Base64 encoded version of the C<port> column value suitable for use
in a URL.

=cut

sub base64url_port { return encode_base64url((shift)->port) }

=head2 net_mac

Returns the C<mac> column instantiated into a L<NetAddr::MAC> object.

=cut

sub net_mac { return NetAddr::MAC->new(mac => (shift)->mac) }

=head2 last_comment

Returns the most recent comment from the logs for this device port.

=cut

sub last_comment {
  my $row = (shift)->logs->search(undef,
    { order_by => { -desc => 'creation' }, rows => 1 })->first;
  return ($row ? $row->log : '');
}

1;
