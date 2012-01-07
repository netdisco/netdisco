use utf8;
package Netdisco::DB::Result::DevicePort;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

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
  "vlan",
  { data_type => "text", is_nullable => 1 },
  "pvid",
  { data_type => "integer", is_nullable => 1 },
  "lastchange",
  { data_type => "bigint", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("port", "ip");


# Created by DBIx::Class::Schema::Loader v0.07015 @ 2012-01-07 14:20:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:lcbweb0loNwHoWUuxTN/hA

__PACKAGE__->belongs_to( device => 'Netdisco::DB::Result::Device', 'ip' );
__PACKAGE__->has_many( port_vlans_tagged => 'Netdisco::DB::Result::DevicePortVlan',
    sub {
        my $args = shift;
        return {
            "$args->{foreign_alias}.ip" => { -ident => "$args->{self_alias}.ip" },
            "$args->{foreign_alias}.port" => { -ident => "$args->{self_alias}.port" },
            -not_bool => "$args->{foreign_alias}.native",
        };
    }
);
__PACKAGE__->many_to_many( tagged_vlans => 'port_vlans_tagged', 'vlan' );
__PACKAGE__->might_have( native_port_vlan => 'Netdisco::DB::Result::DevicePortVlan',
    sub {
        my $args = shift;
        return {
            "$args->{foreign_alias}.ip" => { -ident => "$args->{self_alias}.ip" },
            "$args->{foreign_alias}.port" => { -ident => "$args->{self_alias}.port" },
            -bool => "$args->{foreign_alias}.native",
        };
    }
);
sub native_vlan {
    my $row = shift;
    return eval { $row->native_port_vlan->vlan || undef };
};

1;
