package App::Netdisco::Web::Plugin::Search::VLAN;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_search_tab( { tag => 'vlan', label => 'VLAN' } );

# devices carrying vlan xxx
sub get_rs_vlan {
    my $q = shift;

    my $set;

    if ( $q =~ m/^\d+$/ ) {
        $set = schema('netdisco')->resultset('Device')
            ->carrying_vlan( { vlan => $q } );
    }
    else {
        $set = schema('netdisco')->resultset('Device')
            ->carrying_vlan_name( { name => $q } );
    }
    return $set;
}

ajax '/ajax/content/search/vlan' => require_login sub {
    my $q = param('q');
    send_error( 'Missing query', 400 ) unless $q;

    my $set = get_rs_vlan($q);

    return unless $set->count;

    content_type('text/html');
    template 'ajax/search/vlan.tt', { results => $set, }, { layout => undef };
};

get '/search/vlan' => require_login sub {
    my $q      = param('q');
    my $format = param('format');
    send_error( 'Missing query', 400 ) unless $q;

    my $set = get_rs_vlan($q);

    return unless $set->count;

    if ( $format eq 'csv' ) {

        header( 'Content-Type' => 'text/comma-separated-values' );
        header( 'Content-Disposition' =>
                "attachment; filename=\"nd-vlansearch.csv\"" );
        template 'ajax/search/vlan_csv.tt', { results => $set, },
            { layout => undef };
    }
    else {
        return;
    }
};

true;
