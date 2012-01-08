package Netdisco::DB::ResultSet::Node;
use base 'DBIx::Class::ResultSet';

sub by_mac {
    my ($set, $archive, $mac) = @_;
    return $set unless $mac;

    return $set->search(
      {
        'me.mac' => $mac,
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
