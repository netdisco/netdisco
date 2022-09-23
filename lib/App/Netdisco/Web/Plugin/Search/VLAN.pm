package App::Netdisco::Web::Plugin::Search::VLAN;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_search_tab({
    tag => 'vlan',
    label => 'VLAN',
    provides_csv => 1,
    api_endpoint => 1,
    api_parameters => [
      q => {
        description => 'VLAN name or number',
        required => 1,
      },
    ],
});

# devices carrying vlan xxx
get '/ajax/content/search/vlan' => require_login sub {
    my $q = param('q');
    send_error( 'Missing query', 400 ) unless $q;
    return unless ($q =~ m/\w/); # need some alphanum at least
    my $rs;

    if ( $q =~ m/^\d+$/ ) {
        $rs = schema(vars->{'tenant'})->resultset('Device')
            ->carrying_vlan( { vlan => $q } );
    }
    else {
        $rs = schema(vars->{'tenant'})->resultset('Device')
            ->carrying_vlan_name( { name => $q } );
    }

    my @results = $rs->hri->all;
    return unless scalar @results;

    if (request->is_ajax) {
        my $json = to_json( \@results );
        template 'ajax/search/vlan.tt', { results => $json }, { layout => 'noop' };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/search/vlan_csv.tt', { results => \@results }, { layout => 'noop' };
    }
};

1;
