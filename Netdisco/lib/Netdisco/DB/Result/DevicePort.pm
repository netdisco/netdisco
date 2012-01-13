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

__PACKAGE__->has_many( nodes => 'Netdisco::DB::Result::Node',
    {
      'foreign.switch' => 'self.ip',
      'foreign.port' => 'self.port',
    },
    {
      prefetch => 'ips',
      order_by => 'me.mac',
      '+select' => [
        \"replace(age(me.time_last)::text, 'mon', 'month')",
      ],
      '+as' => [
        'me.time_last',
      ],
    },
);

sub get_nodes {
    my ($row, $archive) = @_;
    return $row->nodes({
      ($archive ? (-or => [{'me.active' => 1}, {'me.active' => 0}])
                : ('me.active' => 1))
    });
}

__PACKAGE__->belongs_to( neighbor_alias => 'Netdisco::DB::Result::DeviceIp',
    {
      'foreign.alias' => 'self.remote_ip',
    },
    {
      join_type => 'left',
    },
);
# FIXME make this more efficient by specifying the full join to DBIC
sub neighbor { return eval { (shift)->neighbor_alias->device } }
__PACKAGE__->belongs_to( device => 'Netdisco::DB::Result::Device', 'ip',
    {
      '+select' => [
        \"replace(age(timestamp 'epoch' + uptime / 100 * interval '1 second', timestamp '1970-01-01 00:00:00-00')::text, 'mon', 'month')",
        \"to_char(last_discover, 'YYYY-MM-DD HH24:MI')",
        \"to_char(last_macsuck,  'YYYY-MM-DD HH24:MI')",
        \"to_char(last_arpnip,   'YYYY-MM-DD HH24:MI')",
      ],
      '+as' => [qw/ uptime last_discover last_macsuck last_arpnip /],
    },
);
__PACKAGE__->has_many( port_vlans_tagged => 'Netdisco::DB::Result::DevicePortVlan',
    {
        'foreign.ip' => 'self.ip',
        'foreign.port' => 'self.port',
    },
    {
        where => { -not_bool => 'me.native' },
    }
);
__PACKAGE__->many_to_many( tagged_vlans => 'port_vlans_tagged', 'vlan' );
# weirdly I could not get row.tagged.vlans.count to work in TT
# so gave up and wrote this instead.
sub tagged_vlans_count {
  return (shift)->tagged_vlans->count;
}
__PACKAGE__->might_have( native_port_vlan => 'Netdisco::DB::Result::DevicePortVlan',
    {
        'foreign.ip' => 'self.ip',
        'foreign.port' => 'self.port',
    },
    {
        where => { -bool => 'me.native' },
    }
);
sub native_vlan {
    my $row = shift;
    return eval { $row->native_port_vlan->vlan || undef };
};

__PACKAGE__->belongs_to( oui => 'Netdisco::DB::Result::Oui',
    sub {
        my $args = shift;
        return {
            "$args->{foreign_alias}.oui" =>
              { '=' => \"substring(cast($args->{self_alias}.mac as varchar) for 8)" }
        };
    }
);

sub is_free {
  my ($row, $num, $unit) = @_;
  return unless $num =~ m/^\d+$/
            and $unit =~ m/(?:days|weeks|months|years)/;

  return 0 unless
    ($row->up_admin and $row->up_admin eq 'up')
    and ($row->up and $row->up eq 'down');

  my $quan = {
    days   => (60 * 60 * 24),
    weeks  => (60 * 60 * 24 * 7),
    months => (60 * 60 * 24 * 31),
    years  => (60 * 60 * 24 * 365),
  };
  my $total = $num * $quan->{$unit};

  my $diff_sec = $row->lastchange / 100;
  return ($diff_sec >= $total ? 1 : 0);
}

1;
