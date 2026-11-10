package App::Netdisco::Web::Plugin::Report::VrfInconsistency;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'IP',
        tag          => 'vrfinconsistency',
        label        => 'VRF Naming Inconsistencies',
        provides_csv => 1,
        api_endpoint => 1,
    }
);

get '/ajax/content/report/vrfinconsistency' => require_login sub {
    my @results = schema(vars->{'tenant'})->resultset('Virtual::VrfInconsistency')
        ->search( undef, { order_by => [qw/ finding domain vrfs /] } )->hri->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        template 'ajax/report/vrfinconsistency.tt', { results => to_json(\@results) }, { layout => 'noop' };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/vrfinconsistency_csv.tt', { results => \@results }, { layout => 'noop' };
    }
};

true;
