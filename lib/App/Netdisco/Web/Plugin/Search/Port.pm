package App::Netdisco::Web::Plugin::Search::Port;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::Web 'sql_match';

register_search_tab( { tag => 'port', label => 'Port', provides_csv => 1 } );

# device ports with a description (er, name) matching
get '/ajax/content/search/port' => require_login sub {
    my $q = param('q');
    send_error( 'Missing query', 400 ) unless $q;
    my $rs;

    if ( $q =~ m/^\d+$/ ) {
        $rs
            = schema('netdisco')->resultset('DevicePort')
            ->columns( [qw/ ip port name up up_admin speed /] )->search({
              "port_vlans.vlan" => $q,
              ( param('uplink') ? () : (-or => [
                {-not_bool => "me.is_uplink"},
                {"me.is_uplink" => undef},
              ]) ),
              ( param('ethernet') ? ("me.type" => 'ethernetCsmacd') : () ),
            },{ '+columns' => [qw/ device.dns device.name port_vlans.vlan /],
                join       => [qw/ port_vlans device /]
            }
            )->with_times;
    }
    else {
        my ( $likeval, $likeclause ) = sql_match($q);

        $rs
            = schema('netdisco')->resultset('DevicePort')
                                ->columns( [qw/ ip port name up up_admin speed /] )
                                ->search({
              -and => [
                -or => [
                  { "me.name" => ( param('partial') ? $likeclause : $q ) },
                  (   length $q == 17
                      ? { "me.mac" => $q }
                      : \[ 'me.mac::text ILIKE ?', $likeval ]
                  ),
                  ( param('uplink') ? (
                    { "me.remote_id"   => $likeclause },
                    { "me.remote_type" => $likeclause },
                  ) : () ),
                ],
                ( param('uplink') ? () : (-or => [
                  {-not_bool => "me.is_uplink"},
                  {"me.is_uplink" => undef},
                ]) ),
                ( param('ethernet') ? ("me.type" => 'ethernetCsmacd') : () ),
              ]
            },
            {   '+columns' => [qw/ device.dns device.name port_vlans.vlan /],
                join       => [qw/ port_vlans device /]
            }
            )->with_times;
    }

    my @results = $rs->hri->all;
    return unless scalar @results;

    if ( request->is_ajax ) {
        my $json = to_json( \@results );
        template 'ajax/search/port.tt', { results => $json },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/search/port_csv.tt', { results => \@results },
            { layout => undef };
    }
};

1;
