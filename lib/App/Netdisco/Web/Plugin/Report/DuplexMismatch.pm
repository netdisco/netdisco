package App::Netdisco::Web::Plugin::Report::DuplexMismatch;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'Port',
        tag          => 'duplexmismatch',
        label        => 'Duplex Mismatches Between Devices',
        provides_csv => 1,
    }
);

get '/ajax/content/report/duplexmismatch' => require_login sub {
    my @results
        = schema('netdisco')->resultset('Virtual::DuplexMismatch')->hri->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        my $json = to_json( \@results );
        template 'ajax/report/duplexmismatch.tt', { results => $json, },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/duplexmismatch_csv.tt',
            { results => \@results, },
            { layout  => undef };
    }
};

1;
