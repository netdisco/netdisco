package App::Netdisco::Web::Plugin::Report::PortUtilization;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category => 'Device',
        tag      => 'portutilization',
        label    => 'Port Utilization',
        provides_csv => 1,
    }
);

get '/ajax/content/report/portutilization' => require_login sub {
    return unless schema('netdisco')->resultset('Device')->count;
    my $set = schema('netdisco')->resultset('Virtual::PortUtilization');

    if (request->is_ajax) {
        template 'ajax/report/portutilization.tt', { results => $set, },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/portutilization_csv.tt', { results => $set, },
            { layout => undef };
    }
};

true;
