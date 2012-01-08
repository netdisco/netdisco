package Netdisco::DB::ResultSet::DevicePort;
use base 'DBIx::Class::ResultSet';

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

1;

