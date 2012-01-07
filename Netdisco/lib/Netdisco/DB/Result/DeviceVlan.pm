use utf8;
package Netdisco::DB::Result::DeviceVlan;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

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


# Created by DBIx::Class::Schema::Loader v0.07015 @ 2012-01-07 14:20:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:hBJRcdzOic4d3u4pD1m8iA

__PACKAGE__->belongs_to( device => 'Netdisco::DB::Result::Device', 'ip' );
__PACKAGE__->has_many( port_vlans_tagged => 'Netdisco::DB::Result::DevicePortVlan',
    sub {
        my $args = shift;
        return {
            "$args->{foreign_alias}.ip" => { -ident => "$args->{self_alias}.ip" },
            "$args->{foreign_alias}.vlan" => { -ident => "$args->{self_alias}.vlan" },
            -not_bool => "$args->{foreign_alias}.native",
        };
    }
);
__PACKAGE__->has_many( port_vlans_native => 'Netdisco::DB::Result::DevicePortVlan',
    sub {
        my $args = shift;
        return {
            "$args->{foreign_alias}.ip" => { -ident => "$args->{self_alias}.ip" },
            "$args->{foreign_alias}.vlan" => { -ident => "$args->{self_alias}.vlan" },
            -bool => "$args->{foreign_alias}.native",
        };
    }
);
__PACKAGE__->many_to_many( tagging_ports => 'port_vlans_tagged', 'port' );
__PACKAGE__->many_to_many( native_ports  => 'port_vlans_native', 'port' );

1;
