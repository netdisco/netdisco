package App::Netdisco::Web::Plugin::Report::DevicePoeStatus;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'Device',
        tag          => 'devicepoestatus',
        label        => 'Power over Ethernet (PoE) Status',
        provides_csv => 1,
    }
);

get '/ajax/content/report/devicepoestatus' => require_login sub {
    my $results = schema('netdisco')->resultset('Device')
        ->with_poestats_as_hashref;

    return unless scalar $results;

    if ( request->is_ajax ) {
        template 'ajax/report/devicepoestatus.tt', { results => $results, },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/devicepoestatus_csv.tt',
            { results => $results, },
            { layout  => undef };
    }
};

1;
