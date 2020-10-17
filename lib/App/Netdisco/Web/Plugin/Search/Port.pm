package App::Netdisco::Web::Plugin::Search::Port;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::Web 'sql_match';

use Regexp::Common 'net';
use NetAddr::MAC ();

register_search_tab({
    tag => 'port',
    label => 'Port',
    provides_csv => 1,
    api_endpoint => 1,
    api_parameters => [
      q => {
        description => 'Port name or VLAN or MAC address',
        required => 1,
      },
      partial => {
        description => 'Search for a partial match on parameter "q"',
        type => 'boolean',
        default => 'true',
      },
      uplink => {
        description => 'Include uplinks in results',
        type => 'boolean',
        default => 'false',
      },
      ethernet => {
        description => 'Only Ethernet type interfaces in results',
        type => 'boolean',
        default => 'true',
      },
    ],
});

# device ports with a description (er, name) matching
get '/ajax/content/search/port' => require_login sub {
    my $q = param('q');
    send_error( 'Missing query', 400 ) unless $q;
    my $rs;

    if ($q =~ m/^[0-9]+$/ and $q < 4096) {
        $rs = schema('netdisco')->resultset('DevicePort')
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
        my $mac = NetAddr::MAC->new(mac => ($q || ''));

        undef $mac if
          ($mac and $mac->as_ieee
          and (($mac->as_ieee eq '00:00:00:00:00:00')
            or ($mac->as_ieee !~ m/$RE{net}{MAC}/)));

        $rs = schema('netdisco')->resultset('DevicePort')
                                ->columns( [qw/ ip port name up up_admin speed /] )
                                ->search({
              -and => [
                -or => [
                  { "me.name" => ( param('partial') ? $likeclause : $q ) },
                  ( ((!defined $mac) or $mac->errstr)
                      ? \[ 'me.mac::text ILIKE ?', $likeval ]
                      : {  'me.mac' => $mac->as_ieee        }
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
        template 'ajax/search/port.tt', { results => $json };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/search/port_csv.tt', { results => \@results };
    }
};

1;
