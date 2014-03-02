package App::Netdisco::Web::Plugin::Search::Port;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::Web 'sql_match';

register_search_tab({ tag => 'port', label => 'Port', provides_csv => 1 });

# device ports with a description (er, name) matching
get '/ajax/content/search/port' => require_login sub {
    my $q = param('q');
    send_error('Missing query', 400) unless $q;
    my $set;

    if ($q =~ m/^\d+$/) {
        $set = schema('netdisco')->resultset('DevicePort')
          ->search({vlan => $q});
    }
    else {
        my ($likeval, $likeclause) = sql_match($q);

        $set = schema('netdisco')->resultset('DevicePort')
          ->search({-or => [
                      {name => (param('partial') ? $likeclause : $q)},
                      (length $q == 17 ? {mac => $q}
                                       : \['mac::text ILIKE ?', $likeval]),
                    ]});
    }
    return unless $set->count;

    if (request->is_ajax) {
        template 'ajax/search/port.tt', {results => $set},
          { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/search/port_csv.tt', {results => $set},
          { layout => undef };
    }
};

true;
