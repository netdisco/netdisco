package App::Netdisco::Web::Plugin::Report::PhonesDiscovered;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category => 'Node',
        tag      => 'phonesdiscovered',
        label    => 'IP Phones discovered through LLDP/CDP',
        provides_csv => 1,
    }
);

get '/ajax/content/report/phonesdiscovered' => require_login sub {
    my $set = schema('netdisco')->resultset('Virtual::PhonesDiscovered');
    return unless $set->count;

    if (request->is_ajax) {
        template 'ajax/report/phonesdiscovered.tt', { results => $set, },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/phonesdiscovered_csv.tt', { results => $set, },
            { layout => undef };
    }
};

true;
