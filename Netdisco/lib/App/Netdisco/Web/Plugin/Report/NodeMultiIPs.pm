package App::Netdisco::Web::Plugin::Report::NodeMultiIPs;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'Node',
        tag          => 'nodemultiips',
        label        => 'Nodes with multiple active IP addresses',
        provides_csv => 1,
    }
);

get '/ajax/content/report/nodemultiips' => require_login sub {
    my $results = schema('netdisco')->resultset('Node')
        ->with_multi_ips_as_hashref;

    return unless scalar $results;

    if ( request->is_ajax ) {
        template 'ajax/report/nodemultiips.tt', { results => $results, },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/nodemultiips_csv.tt',
            { results => $results, },
            { layout  => undef };
    }
};

1;
