use utf8;
package Netdisco::DB::Result::Node;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("node");
__PACKAGE__->add_columns(
  "mac",
  { data_type => "macaddr", is_nullable => 0 },
  "switch",
  { data_type => "inet", is_nullable => 0 },
  "port",
  { data_type => "text", is_nullable => 0 },
  "active",
  { data_type => "boolean", is_nullable => 1 },
  "oui",
  { data_type => "varchar", is_nullable => 1, size => 8 },
  "time_first",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
  "time_recent",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
  "time_last",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
);
__PACKAGE__->set_primary_key("mac", "switch", "port");


# Created by DBIx::Class::Schema::Loader v0.07015 @ 2012-01-07 14:20:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:sGGyKEfUkoIFVtmj1wnH7A

__PACKAGE__->belongs_to( device => 'Netdisco::DB::Result::Device',
  { 'foreign.ip' => 'self.switch' }, { join_type => 'LEFT' } );

# device port may have been deleted (reconfigured modules?) but node remains
__PACKAGE__->belongs_to( device_port => 'Netdisco::DB::Result::DevicePort',
  { 'foreign.ip' => 'self.switch', 'foreign.port' => 'self.port' },
  { join_type => 'LEFT' }
);

__PACKAGE__->has_many( ips => 'Netdisco::DB::Result::NodeIp',
  { 'foreign.mac' => 'self.mac', 'foreign.active' => 'self.active' } );

__PACKAGE__->belongs_to( oui => 'Netdisco::DB::Result::Oui', 'oui' );

# accessors for custom formatted columns
sub time_first_stamp { return (shift)->get_column('time_first_stamp') }
sub time_last_stamp  { return (shift)->get_column('time_last_stamp')  }

1;
