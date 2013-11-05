package App::Netdisco::Web::Plugin::Report::DeviceAddrNoDNS;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'Device',
        tag          => 'deviceaddrnodns',
        label        => 'Addresses without DNS Entries',
        provides_csv => 1,
    }
);

get '/ajax/content/report/deviceaddrnodns' => require_login sub {
    my $results = schema('netdisco')->resultset('Device')
        ->address_nodns_as_hashref;

    return unless scalar $results;

    if ( request->is_ajax ) {
        template 'ajax/report/deviceaddrnodns.tt', { results => $results, },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/deviceaddrnodns_csv.tt',
            { results => $results, },
            { layout  => undef };
    }
};

1;
