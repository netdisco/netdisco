use utf8;
package Netdisco::DB::Result::NodeIp;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("node_ip");
__PACKAGE__->add_columns(
  "mac",
  { data_type => "macaddr", is_nullable => 0 },
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "active",
  { data_type => "boolean", is_nullable => 1 },
  "time_first",
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
  "dns",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("mac", "ip");


# Created by DBIx::Class::Schema::Loader v0.07015 @ 2012-01-07 14:20:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:9+CuvuVWH88WxAf6IBij8g

__PACKAGE__->has_many( nodeips => 'Netdisco::DB::Result::NodeIp',
  { 'foreign.mac' => 'self.mac' } );
__PACKAGE__->has_many( nodes => 'Netdisco::DB::Result::Node',
  { 'foreign.mac' => 'self.mac' } );

sub tidy_nodeips {
    my ($row, $archive) = @_;

    return $row->nodeips(
      {
        ip  => { '!=' => $row->ip },
        ($archive ? () : (active => 1)),
      },
      {
        order_by => {'-desc' => 'time_last'},
        columns => [qw/ mac ip dns active /],
        '+select' => [
          \"to_char(time_first, 'YYYY-MM-DD HH24:MI')",
          \"to_char(time_last, 'YYYY-MM-DD HH24:MI')",
        ],
        '+as' => [qw/ time_first time_last /],
      },
    );
}

sub tidy_nodes {
    my ($row, $archive) = @_;

    return $row->nodes(
      {
        ($archive ? () : (active => 1)),
      },
      {
        order_by => {'-desc' => 'time_last'},
        columns => [qw/ mac switch port oui active device.dns /],
        '+select' => [
          \"to_char(time_first, 'YYYY-MM-DD HH24:MI')",
          \"to_char(time_last, 'YYYY-MM-DD HH24:MI')",
        ],
        '+as' => [qw/ time_first time_last /],
        join => 'device',
      },
    );
}

1;
