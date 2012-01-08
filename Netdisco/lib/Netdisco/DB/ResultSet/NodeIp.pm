package Netdisco::DB::ResultSet::NodeIp;
use base 'DBIx::Class::ResultSet';

sub by_ip {
    my ($set, $ip, $archive) = @_;
    return $set unless $ip;

    return $set->search(
      {
        ip => $ip,
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

1;
