package App::Netdisco::Web::Plugin::Report::PortVLANMismatch;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category => 'Port',
        tag      => 'portvlanmismatch',
        label    => 'Port VLAN Mismatches',
        provides_csv => 1,
        api_endpoint => 1,
    }
);

get '/ajax/content/report/portvlanmismatch' => require_login sub {
    return unless schema('netdisco')->resultset('Device')->count;
    my @results = schema('netdisco')->resultset('Virtual::PortVLANMismatch')->hri->all;

    if (request->is_ajax) {
        my $json = to_json (\@results);
        template 'ajax/report/portvlanmismatch.tt', { results => $json }, { layout => 'noop' };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/portvlanmismatch_csv.tt', { results => \@results, }, { layout => 'noop' };
    }
};

1;
