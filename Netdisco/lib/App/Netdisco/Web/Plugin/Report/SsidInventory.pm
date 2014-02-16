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
    my $rs = schema('netdisco')->resultset('DevicePortSsid')->get_ssids->hri;
    return unless $rs->has_rows;

    if ( request->is_ajax ) {
        template 'ajax/report/portssid.tt', { results => $rs, },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/portssid_csv.tt', { results => $rs, },
            { layout => undef };
    }
};

1;
