package App::Netdisco::Web::Plugin::Search::VLAN;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_search_tab( { tag => 'vlan', label => 'VLAN', provides_csv => 1 } );

# devices carrying vlan xxx
get '/ajax/content/search/vlan' => require_login sub {
    my $q = param('q');
    send_error( 'Missing query', 400 ) unless $q;
    my $set;

    if ( $q =~ m/^\d+$/ ) {
        $set = schema('netdisco')->resultset('Device')
            ->carrying_vlan( { vlan => $q } );
    }
    else {
        $set = schema('netdisco')->resultset('Device')
            ->carrying_vlan_name( { name => $q } );
    }
    return unless $set->count;

    if (request->is_ajax) {
        template 'ajax/search/vlan.tt', { results => $set },
          { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/search/vlan_csv.tt', { results => $set },
          { layout => undef };
    }
};

true;
