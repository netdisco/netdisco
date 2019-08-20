use utf8;
package App::Netdisco::DB::Result::DeviceVlan;


use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("device_vlan");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "vlan",
  { data_type => "integer", is_nullable => 0 },
  "description",
  { data_type => "text", is_nullable => 1 },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
  "last_discover",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
);
__PACKAGE__->set_primary_key("ip", "vlan");



=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table on which this VLAN entry was discovered.

=cut

__PACKAGE__->belongs_to( device => 'App::Netdisco::DB::Result::Device', 'ip' );

=head2 port_vlans_tagged

Link relationship for C<tagged_ports>, see below.

=cut

__PACKAGE__->has_many( port_vlans_tagged => 'App::Netdisco::DB::Result::DevicePortVlan',
    sub {
      my $args = shift;
      return {
        "$args->{foreign_alias}.ip"   => { -ident => "$args->{self_alias}.ip" },
        "$args->{foreign_alias}.vlan" => { -ident => "$args->{self_alias}.vlan" },
        -not_bool => "$args->{foreign_alias}.native",
      };
    },
    { cascade_copy => 0, cascade_update => 0, cascade_delete => 0 }
);

=head2 port_vlans_untagged

Link relationship to support C<untagged_ports>, see below.

=cut

__PACKAGE__->has_many( port_vlans_untagged => 'App::Netdisco::DB::Result::DevicePortVlan',
    sub {
      my $args = shift;
      return {
        "$args->{foreign_alias}.ip"   => { -ident => "$args->{self_alias}.ip" },
        "$args->{foreign_alias}.vlan" => { -ident => "$args->{self_alias}.vlan" },
        -bool => "$args->{foreign_alias}.native",
      };
    },
    { cascade_copy => 0, cascade_update => 0, cascade_delete => 0 }
);

=head2 ports

Link relationship to support C<ports>.

=cut

__PACKAGE__->has_many( ports => 'App::Netdisco::DB::Result::DevicePortVlan',
    { 'foreign.ip' => 'self.ip', 'foreign.vlan' => 'self.vlan' },
    { cascade_copy => 0, cascade_update => 0, cascade_delete => 0 }
);

=head2 tagged_ports

Returns the set of Device Ports on which this VLAN is configured to be tagged.

=cut

__PACKAGE__->many_to_many( tagged_ports => 'port_vlans_tagged', 'port' );

=head2 untagged_ports

Returns the set of Device Ports on which this VLAN is an untagged VLAN.

=cut

__PACKAGE__->many_to_many( untagged_ports  => 'port_vlans_untagged', 'port' );

1;
