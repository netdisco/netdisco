package App::Netdisco::Web::Plugin::Report::IpInventory;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use NetAddr::IP::Lite ':lower';
use POSIX qw/strftime/;

register_report(
    {   category     => 'IP',
        tag          => 'ipinventory',
        label        => 'IP Inventory',
        provides_csv => 1,
        api_endpoint => 1,
        api_parameters => [
          subnet => {
            description => 'IP Prefix to search',
            required => 1,
          },
          daterange => {
            description => 'Date range to search',
            default => ('1970-01-01 to '. strftime('%Y-%m-%d', gmtime)),
          },
          age_invert => {
            description => 'Results should NOT be within daterange',
            type => 'boolean',
            default => 'false',
          },
          limit => {
            description => 'Maximum number of historical records',
            enum => [qw/32 64 128 256 512 1024 2048 4096 8192/],
            default => '2048',
          },
          never => {
            description => 'Include in the report IPs never seen',
            type => 'boolean',
            default => 'false',
          },
        ],
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

    my $daterange = param('daterange')
      || ('1970-01-01 to '. strftime('%Y-%m-%d', gmtime));
    my ( $start, $end ) = $daterange =~ /(\d+-\d+-\d+)/gmx;

    my $limit = param('limit') || 256;
    my $never = param('never') || '0';
    my $order = [{-desc => 'age'}, {-asc => 'ip'}];

    # We need a reasonable limit to prevent a potential DoS, especially if
    # 'never' is true.  TODO: Need better input validation, both JS and
    # server-side to provide user feedback
    $limit = 8192 if $limit > 8192;

    my $rs1 = schema(vars->{'tenant'})->resultset('DeviceIp')->search(
        undef,
        {   join   => ['device', 'device_port'],
            select => [
                'alias AS ip',
                'device_port.mac as mac',
                'creation AS time_first',
                'device.last_discover AS time_last',
                'dns',
                \'true AS active',
                \'false AS node',
                \qq/replace( date_trunc( 'minute', age( LOCALTIMESTAMP, device.last_discover ) ) ::text, 'mon', 'month') AS age/,
                'device.vendor',
                \'null AS nbname',

            ],
            as => [qw( ip mac time_first time_last dns active node age vendor nbname)],
        }
    )->hri;

    my $rs2 = schema(vars->{'tenant'})->resultset('NodeIp')->search(
        undef,
        {   join   => ['manufacturer', 'netbios'],
            columns   => [qw( ip mac time_first time_last dns active)],
            '+select' => [ \'true AS node',
                           \qq/replace( date_trunc( 'minute', age( LOCALTIMESTAMP, me.time_last ) ) ::text, 'mon', 'month') AS age/,
                           'manufacturer.company',
                           'netbios.nbname',
                         ],
            '+as'     => [ 'node', 'age', 'vendor', 'nbname' ],
        }
    )->hri;

    my $rs3 = schema(vars->{'tenant'})->resultset('NodeNbt')->search(
        undef,
        {   join   => ['manufacturer'],
            columns   => [qw( ip mac time_first time_last )],
            '+select' => [
                \'null AS dns',
                'active',
                \'true AS node',
                \qq/replace( date_trunc( 'minute', age( LOCALTIMESTAMP, time_last ) ) ::text, 'mon', 'month') AS age/,
                'manufacturer.company',
                'nbname'
            ],
            '+as' => [ 'dns', 'active', 'node', 'age', 'vendor', 'nbname' ],
        }
    )->hri;

    my $rs_union = $rs1->union( [ $rs2, $rs3 ] );

    if ( $never ) {
        $subnet = NetAddr::IP::Lite->new('0.0.0.0/32') if ($subnet->bits ne 32);

        my $rs4 = schema(vars->{'tenant'})->resultset('Virtual::CidrIps')->search(
            undef,
            {   bind => [ $subnet->cidr ],
                columns   => [qw( ip mac time_first time_last dns active node age vendor nbname )],
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
                'age',
                'vendor',
                'nbname'
            ],
            as => [
                'ip',     'mac',  'dns', 'time_last', 'time_first',
                'active', 'node', 'age', 'vendor', 'nbname'
            ],
            order_by => [{-asc => 'ip'}, {-asc => 'dns'}, {-desc => 'active'}, {-asc => 'node'}],
        }
    )->as_query;

    my $rs;
    if ( $start and $end ) {
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
        template 'ajax/report/ipinventory.tt', { results => $json }, { layout => 'noop' };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/ipinventory_csv.tt', { results => \@results, }, { layout => 'noop' };
    }
};

1;
