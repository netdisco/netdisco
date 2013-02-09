package App::Netdisco::Web::Plugin::Search::Device;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use List::MoreUtils ();

use App::Netdisco::Web::Plugin;

register_search_tab({id => 'device', label => 'Device'});

# device with various properties or a default match-all
ajax '/ajax/content/search/device' => sub {
    my $has_opt = List::MoreUtils::any {param($_)}
      qw/name location dns ip description model os_ver vendor/;
    my $set;

    if ($has_opt) {
        $set = schema('netdisco')->resultset('Device')->search_by_field(scalar params);
    }
    else {
        my $q = param('q');
        return unless $q;

        $set = schema('netdisco')->resultset('Device')->search_fuzzy($q);
    }
    return unless $set->count;

    content_type('text/html');
    template 'ajax/search/device.tt', {
      results => $set,
    }, { layout => undef };
};

true;
