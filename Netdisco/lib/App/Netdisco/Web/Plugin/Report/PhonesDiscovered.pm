package App::Netdisco::Web::Plugin::Report::PhonesDiscovered;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'Node',
        tag          => 'phonesdiscovered',
        label        => 'IP Phones discovered through LLDP/CDP',
        provides_csv => 1,
    }
);

get '/ajax/content/report/phonesdiscovered' => require_login sub {
    my @results = schema('netdisco')->resultset('Virtual::PhonesDiscovered')
        ->hri->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        my $json = to_json( \@results );
        template 'ajax/report/phonesdiscovered.tt', { results => $json },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/phonesdiscovered_csv.tt',
            { results => \@results },
            { layout  => undef };
    }
};

1;
