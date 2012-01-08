package Netdisco::DB::ResultSet::NodeIp;
use base 'DBIx::Class::ResultSet';

# some customize their node_ip table to have a dns column which
# is the cached record at the time of discovery
sub has_dns_col {
    my $set = shift;
    return $set->result_source->has_column('dns');
}

my $search_attr = {
    order_by => {'-desc' => 'time_last'},
    columns => [qw/ mac ip active oui.company /],
    '+select' => [
      \"to_char(time_first, 'YYYY-MM-DD HH24:MI')",
      \"to_char(time_last, 'YYYY-MM-DD HH24:MI')",
    ],
    '+as' => [qw/ time_first time_last /],
    join => 'oui'
};

sub by_ip {
    my ($set, $archive, $ip) = @_;
    return $set unless $ip;

    my $op = '=';
    if ('NetAddr::IP::Lite' eq ref $ip) {
        $op = '<<=' if $ip->num > 1;
        $ip = $ip->cidr;
    }

    return $set->search(
      {
        ip => { $op => $ip },
        ($archive ? () : (active => 1)),
      },
      {
        %$search_attr,
        ( $set->has_dns_col ? ('+columns' => 'dns') : () ),
      }
    );
}

sub by_name {
    my ($set, $archive, $name) = @_;
    return $set unless $name;

    return $set->search(
      {
        dns => { '-ilike' => $name },
        ($archive ? () : (active => 1)),
      },
      {
        %$search_attr,
        ( $set->has_dns_col ? ('+columns' => 'dns') : () ),
      }
    );
}

1;
