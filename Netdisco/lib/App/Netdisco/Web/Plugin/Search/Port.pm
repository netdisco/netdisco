package App::Netdisco::Web::Plugin::Search::Port;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_search_tab({ tag => 'port', label => 'Port' });

sub get_rs_port {
    my $q = shift;

    my $set;

    if ($q =~ m/^\d+$/) {
        $set = schema('netdisco')->resultset('DevicePort')
          ->search({vlan => $q});
    }
    else {
        my $query = $q;
        if (param('partial')) {
            $q = "\%$q\%" if $q !~ m/%/;
            $query = { -ilike => $q };
        }
        $set = schema('netdisco')->resultset('DevicePort')
          ->search({name => $query});
    }
    return $set;
}

# device ports with a description (er, name) matching
ajax '/ajax/content/search/port' => require_login sub {
    my $q = param('q');
    send_error('Missing query', 400) unless $q;
    
    my $set = get_rs_port($q);

    return unless $set->count;

    content_type('text/html');
    template 'ajax/search/port.tt', {
      results => $set,
    }, { layout => undef };
};

get '/search/port' => require_login sub {
    my $q = param('q');
    my $format = param('format');
    send_error('Missing query', 400) unless $q;

    my $set = get_rs_port($q);

    return unless $set->count;

    if ( $format eq 'csv' ) {
        
        header( 'Content-Type' => 'text/comma-separated-values' );
        header( 'Content-Disposition' =>
                "attachment; filename=\"nd-portsearch.csv\"" );
        template 'ajax/search/port_csv.tt', {
      results => $set,
    }, { layout => undef };
    }
    else {
        return;
    }
};

true;
