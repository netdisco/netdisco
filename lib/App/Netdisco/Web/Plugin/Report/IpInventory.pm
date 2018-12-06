package App::Netdisco::Web::Plugin::Report::IpInventory;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use NetAddr::IP::Lite ':lower';

register_report(
    {   category     => 'IP',
        tag          => 'ipinventory',
        label        => 'IP Inventory',
        provides_csv => 1,
    }
);

get '/ajax/content/report/ipinventory' => require_login sub {

    # Default to something simple with no results to prevent
    # "Search failed!" error
    (my $subnet = (param('subnet') || '0.0.0.0/32')) =~ s/\s//g;
    $subnet = NetAddr::IP::Lite->new($subnet);
    $subnet = NetAddr::IP::Lite->new('0.0.0.0/32')
      if (! $subnet) or ($subnet->addr eq '0.0.0.0');

    my $agenot = param('age_invert') || '0';
    my ( $start, $end ) = param('daterange') =~ /(\d+-\d+-\d+)/gmx;

    my $limit = param('limit') || 256;
    my $never = param('never') || '0';
    my $order = [{-desc => 'age'}, {-asc => 'ip'}];

    # We need a reasonable limit to prevent a potential DoS, especially if
    # 'never' is true.  TODO: Need better input validation, both JS and
    # server-side to provide user feedback
    $limit = 8192 if $limit > 8192;

    my $rs1 = schema('netdisco')->resultset('DeviceIp')->search(
        undef,
        {   join   => 'device',
            select => [
                'alias AS ip',
                \'NULL::macaddr as mac',
                'creation AS time_first',
                'device.last_discover AS time_last',
                'dns',
                \'true AS active',
                \'false AS node',
                \qq/replace( date_trunc( 'minute', age( now(), device.last_discover ) ) ::text, 'mon', 'month') AS age/
            ],
            as => [qw( ip mac time_first time_last dns active node age)],
        }
    )->hri;

    my $rs2 = schema('netdisco')->resultset('NodeIp')->search(
        undef,
        {   columns   => [qw( ip mac time_first time_last dns active)],
            '+select' => [ \'true AS node',
                           \qq/replace( date_trunc( 'minute', age( now(), time_last ) ) ::text, 'mon', 'month') AS age/
                         ],
            '+as'     => [ 'node', 'age' ],
        }
    )->hri;

    my $rs3 = schema('netdisco')->resultset('NodeNbt')->search(
        undef,
        {   columns   => [qw( ip mac time_first time_last )],
            '+select' => [
                'nbname AS dns', 'active',
                \'true AS node',
                \qq/replace( date_trunc( 'minute', age( now(), time_last ) ) ::text, 'mon', 'month') AS age/ 
            ],
            '+as' => [ 'dns', 'active', 'node', 'age' ],
        }
    )->hri;

    my $rs_union = $rs1->union( [ $rs2, $rs3 ] );

    if ( $never ) {
        $subnet = NetAddr::IP::Lite->new('0.0.0.0/32') if ($subnet->bits ne 32);

        my $rs4 = schema('netdisco')->resultset('Virtual::CidrIps')->search(
            undef,
            {   bind => [ $subnet->cidr ],
                columns   => [qw( ip mac time_first time_last dns active)],
                '+select' => [ \'false AS node',
                               \qq/replace( date_trunc( 'minute', age( now(), time_last ) ) ::text, 'mon', 'month') AS age/
                             ],
                '+as'     => [ 'node', 'age' ],
            }
        )->hri;

        $rs_union = $rs_union->union( [$rs4] );
    }

    my $rs_sub = $rs_union->search(
        { ip => { '<<' => $subnet->cidr } },
        {   select   => [
                \'DISTINCT ON (ip) ip',
                'mac',
                'dns',
                \qq/date_trunc('second', time_last) AS time_last/,
                \qq/date_trunc('second', time_first) AS time_first/,
                'active',
                'node',
                'age'
            ],
            as => [
                'ip',     'mac',  'dns',  'time_last', 'time_first',
                'active', 'node', 'age'
            ],
            order_by => [{-asc => 'ip'}, {-desc => 'active'}],
        }
    )->as_query;

    my $rs;
    if ( $start && $end ) {
        $start = $start . ' 00:00:00';
        $end   = $end . ' 23:59:59';

        if ( $agenot ) {
            $rs = $rs_union->search(
                {   -or => [
                        time_first => [ undef ],
                        time_last => [ { '<', $start }, { '>', $end } ]
                    ]
                },
                { from => { me => $rs_sub }, }
            );
        }
        else {
            $rs = $rs_union->search(
                {   -or => [
                      -and => [
                          time_first => undef,
                          time_last  => undef,
                      ],
                      -and => [
                          time_last => { '>=', $start },
                          time_last => { '<=', $end },
                      ],
                    ],
                },
                { from => { me => $rs_sub }, }
            );
        }
    }
    else {
        $rs = $rs_union->search( undef, { from => { me => $rs_sub }, } );
    }

    my @results = $rs->order_by($order)->limit($limit)->all;
    return unless scalar @results;

    if ( request->is_ajax ) {
        my $json = to_json( \@results );
        template 'ajax/report/ipinventory.tt', { results => $json },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/ipinventory_csv.tt', { results => \@results, },
            { layout => undef };
    }
};

1;
