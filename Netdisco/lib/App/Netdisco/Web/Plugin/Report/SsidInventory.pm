package App::Netdisco::Web::Plugin::Report::SsidInventory;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'Wireless',
        tag          => 'ssidinventory',
        label        => 'SSID Inventory',
        provides_csv => 1,
    }
);

get '/ajax/content/report/ssidinventory' => require_login sub {
    my @results = schema('netdisco')->resultset('DevicePortSsid')
        ->get_ssids->hri->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        my $json = to_json( \@results );
        template 'ajax/report/portssid.tt', { results => $json },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/portssid_csv.tt', { results => \@results },
            { layout => undef };
    }
};

1;
