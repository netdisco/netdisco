package App::Netdisco::Web::Plugin::Search::VLAN;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use App::Netdisco::Web::Plugin;

register_search_tab({ tag => 'vlan', label => 'VLAN' });

# devices carrying vlan xxx
ajax '/ajax/content/search/vlan' => sub {
    my $q = param('q');
    return unless $q;
    my $set;

    if ($q =~ m/^\d+$/) {
        $set = schema('netdisco')->resultset('Device')->carrying_vlan({vlan => $q});
    }
    else {
        $set = schema('netdisco')->resultset('Device')->carrying_vlan_name({name => $q});
    }
    return unless $set->count;

    content_type('text/html');
    template 'ajax/search/vlan.tt', {
      results => $set,
    }, { layout => undef };
};

true;
