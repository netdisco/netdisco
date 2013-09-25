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
    my $set = schema('netdisco')->resultset('DevicePortSsid')->search(
        {},
        {   select => [ 'ssid', 'broadcast', { count => 'ssid' } ],
            as       => [qw/ ssid broadcast scount /],
            group_by => [qw/ ssid broadcast /],
            order_by => { -desc => [qw/count/] },
        }
    );
    return unless $set->count;

    if ( request->is_ajax ) {
        template 'ajax/report/ssidinventory.tt', { results => $set, },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/ssidinventory_csv.tt', { results => $set, },
            { layout => undef };
    }
};

true;
