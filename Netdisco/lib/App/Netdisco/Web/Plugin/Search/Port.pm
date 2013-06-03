package App::Netdisco::Web::Plugin::Search::Port;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use App::Netdisco::Web::Plugin;

register_search_tab({ tag => 'port', label => 'Port' });

# device ports with a description (er, name) matching
ajax '/ajax/content/search/port' => sub {
    my $q = param('q');
    send_error('Missing query', 400) unless $q;
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
    return unless $set->count;

    content_type('text/html');
    template 'ajax/search/port.tt', {
      results => $set,
    }, { layout => undef };
};

true;
