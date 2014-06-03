package App::Netdisco::Web::Plugin::Search::Device;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use List::MoreUtils ();

use App::Netdisco::Web::Plugin;

register_search_tab(
    { tag => 'device', label => 'Device', provides_csv => 1 } );

# device with various properties or a default match-all
get '/ajax/content/search/device' => require_login sub {
    my $has_opt = List::MoreUtils::any { param($_) }
    qw/name location dns ip description model os_ver vendor layers/;
    my $rs;

    if ($has_opt) {
        $rs = schema('netdisco')->resultset('Device')->columns(
            [   "ip",       "dns",   "name",   "contact",
                "location", "model", "os_ver", "serial"
            ]
        )->with_times->search_by_field( scalar params );
    }
    else {
        my $q = param('q');
        send_error( 'Missing query', 400 ) unless $q;

        $rs = schema('netdisco')->resultset('Device')->columns(
            [   "ip",       "dns",   "name",   "contact",
                "location", "model", "os_ver", "serial"
            ]
        )->with_times->search_fuzzy($q);
    }

    my @results = $rs->hri->all;
    return unless scalar @results;

    if ( request->is_ajax ) {
        my $json = to_json( \@results );
        template 'ajax/search/device.tt', { results => $json },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/search/device_csv.tt', { results => \@results, },
            { layout => undef };
    }
};

1;
