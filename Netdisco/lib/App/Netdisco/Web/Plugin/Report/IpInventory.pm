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

# Following two Perl Core 5.10+
use Time::Piece;
use Time::Seconds;

hook 'before' => sub {

    return
        unless ( request->path eq uri_for('/report/ipinventory')->path
        or index( request->path, uri_for('/ajax/content/report/ipinventory')->path )
        == 0 );

    my $start = Time::Piece->new - ONE_DAY * 29;

    params->{'limit'} ||= 256;
    params->{'daterange'}
        ||= $start->ymd . " to " . Time::Piece->new->ymd;
};

get '/ajax/content/report/ipinventory' => require_login sub {

    # Default to something simple with no results to prevent
    # "Search failed!" error
    my $subnet = param('subnet') || '0.0.0.0/32';
    $subnet = NetAddr::IP::Lite->new($subnet);
    $subnet = NetAddr::IP::Lite->new('0.0.0.0/32')
      if (! $subnet) or ($subnet->addr eq '0.0.0.0');

    my $age    = param('age_on')     || '0';
    my $agenot = param('age_invert') || '0';

    my ( $start, $end ) = param('daterange') =~ /(\d+-\d+-\d+)/gmx;

    my $limit = param('limit') || 256;
    my $order = param('order') || 'IP';
    my $never = param('never') || '0';

    # We need a reasonable limit to prevent a potential DoS, especially if
    # 'never' is true.  TODO: Need better input validation, both JS and
    # server-side to provide user feedback
    $limit = 8192 if $limit > 8192;
    $order = $order eq 'IP' ? \'ip ASC' : \'age DESC';

    my $rs1 = schema('netdisco')->resultset('DeviceIp')->search(
        undef,
        {   join   => 'device',
            select => [
                'alias AS ip',
                'creation AS time_first',
                'device.last_discover AS time_last',
                'dns',
                \'true AS active',
                \'false AS node',
                \'age(device.last_discover) AS age'
            ],
            as => [qw( ip time_first time_last dns active node age)],
        }
    )->hri;

    my $rs2 = schema('netdisco')->resultset('NodeIp')->search(
        undef,
        {   columns   => [qw( ip time_first time_last dns active)],
            '+select' => [ \'true AS node', \'age(time_last) AS age' ],
            '+as'     => [ 'node', 'age' ],
        }
    )->hri;

    my $rs3 = schema('netdisco')->resultset('NodeNbt')->search(
        undef,
        {   columns   => [qw( ip time_first time_last )],
            '+select' => [
                'nbname AS dns', 'active',
                \'true AS node', \'age(time_last) AS age'
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
                columns   => [qw( ip time_first time_last dns active)],
                '+select' => [ \'false AS node', \'age(time_last) AS age' ],
                '+as'     => [ 'node', 'age' ],
            }
        )->hri;

        $rs_union = $rs_union->union( [$rs4] );
    }

    my $rs_sub = $rs_union->search(
        { ip => { '<<' => $subnet->cidr } },
        {   order_by => [qw( ip time_last )],
            select   => [
                \'DISTINCT ON (ip) ip',
                'dns',
                \'date_trunc(\'second\', time_last) AS time_last',
                \'date_trunc(\'second\', time_first) AS time_first',
                'active',
                'node',
                'age'
            ],
            as => [
                'ip',     'dns',  'time_last', 'time_first',
                'active', 'node', 'age'
            ],
        }
    )->as_query;

    my $rs;
    if ( $age && $start && $end ) {
        $start = $start . ' 00:00:00';
        $end   = $end . ' 23:59:59';

        if ( $agenot ) {
            $rs = $rs_union->search(
                {   -or => [
                        time_first => [ { '<', $start }, undef ],
                        time_last => { '>', $end },
                    ]
                },
                { from => { me => $rs_sub }, }
            );
        }
        else {
            $rs = $rs_union->search(
                {   -and => [
                        time_first => { '>=', $start },
                        time_last  => { '<=', $end },
                    ]
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
        template 'ajax/report/ipinventory.tt', { results => \@results, },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/ipinventory_csv.tt', { results => \@results, },
            { layout => undef };
    }
};

1;
