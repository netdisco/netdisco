use utf8;
package Netdisco::DB::Result::Device;

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


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
