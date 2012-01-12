package Netdisco::DB::ResultSet::DevicePort;
use base 'DBIx::Class::ResultSet';

use strict;
use warnings FATAL => 'all';

sub by_ip {
    my ($set, $ip) = @_;
    return $set unless $ip;

    return $set->search(
      {
        'me.ip' => $ip,
      },
      {
        '+select' => [
          \"to_char(last_discover - (uptime - lastchange) / 100 * interval '1 second', 'YYYY-MM-DD HH24:MI:SS')",
        ],
        '+as' => [qw/ lastchange_stamp /],
        join => 'device',
      }
    );
}

sub by_mac {
    my ($set, $mac) = @_;
    return $set unless $mac;

    return $set->search(
      {
        'me.mac' => $mac,
      },
      {
        order_by => {'-desc' => 'me.creation'},
        columns => [qw/ ip port device.dns /],
        '+select' => [
          \"to_char(me.creation, 'YYYY-MM-DD HH24:MI')",
        ],
        '+as' => [qw/ creation /],
        join => 'device',
      },
    );
}

# confusingly the "name" field is set using IOS "descrption"
# command but should not be confused with the "descr" field
sub by_name {
    my ($set, $name) = @_;
    return $set unless $name;
    $name = "\%$name\%" if $name !~ m/\%/;

    return $set->search(
      {
        'me.name' => { '-ilike' => $name },
      },
      {
        order_by => [qw/ me.ip me.port /],
        columns => [qw/ ip port descr name vlan device.dns /],
        join => 'device',
      },
    );
}

# should match edge ports only
sub by_vlan {
    my ($set, $vlan) = @_;
    return $set unless $vlan and $vlan =~ m/^\d+$/;

    return $set->search(
      {
        'me.vlan' => $vlan,
      },
      {
        order_by => [qw/ me.ip me.port /],
        columns => [qw/ ip port descr name vlan device.dns /],
        join => 'device',
      },
    );
}

sub by_port {
    my ($set, $port) = @_;
    return $set unless $port;

    return $set->search(
      {
        'me.port' => $port,
      },
      {
        order_by => [qw/ me.ip me.port /],
        columns => [qw/ ip port descr name vlan device.dns /],
        join => 'device',
      },
    );
}

1;

