package App::Netdisco::Web::Plugin::Search::Device;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use List::MoreUtils ();

use App::Netdisco::Web::Plugin;

register_search_tab({ tag => 'device', label => 'Device', provides_csv => 1 });

my $headers = ['Device','Contact','Location','System Name','Model','OS Version','Management IP','Serial'];

# device with various properties or a default match-all
get '/ajax/content/search/device' => require_login sub {
    my $has_opt = List::MoreUtils::any {param($_)}
      qw/name location dns ip description model os_ver vendor layers/;
    my $set;

    if ($has_opt) {
        $set = schema('netdisco')->resultset('Device')
          ->with_times->search_by_field(scalar params);
    }
    else {
        my $q = param('q');
        send_error('Missing query', 400) unless $q;

        $set = schema('netdisco')->resultset('Device')
          ->with_times->search_fuzzy($q);
    }
    return unless $set->count;

    if (request->is_ajax) {
        template 'ajax/search/device.tt', {results => $set},
          { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/search/device_csv.tt', {
          results => $set,
          headers => $headers,
        }, { layout => undef };
    }
};

true;
