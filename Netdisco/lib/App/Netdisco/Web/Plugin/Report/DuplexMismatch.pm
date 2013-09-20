package App::Netdisco::Web::Plugin::Report::DuplexMismatch;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category => 'Port',
        tag      => 'duplexmismatch',
        label    => 'Duplex Mismatches Between Devices',
        provides_csv => 1,
    }
);

get '/ajax/content/report/duplexmismatch' => require_login sub {
    my $set = schema('netdisco')->resultset('Virtual::DuplexMismatch');
    return unless $set->count;

    if (request->is_ajax) {
        template 'ajax/report/duplexmismatch.tt', { results => $set, },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/duplexmismatch_csv.tt', { results => $set, },
            { layout => undef };
    }
};

true;
