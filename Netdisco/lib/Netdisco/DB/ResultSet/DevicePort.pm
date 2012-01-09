package Netdisco::DB::ResultSet::DevicePort;
use base 'DBIx::Class::ResultSet';

use strict;
use warnings FATAL => 'all';

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

1;

