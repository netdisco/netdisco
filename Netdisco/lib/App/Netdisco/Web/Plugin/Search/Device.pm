package App::Netdisco::Web::Plugin::Search::Device;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use List::MoreUtils ();

use App::Netdisco::Web::Plugin;

register_search_tab({ tag => 'device', label => 'Device' });

# device with various properties or a default match-all
ajax '/ajax/content/search/device' => require_login sub {
    my $has_opt = List::MoreUtils::any {param($_)}
      qw/name location dns ip description model os_ver vendor/;
    my $set;

    if ($has_opt) {
        $set = schema('netdisco')->resultset('Device')->search_by_field(scalar params);
    }
    else {
        my $q = param('q');
        send_error('Missing query', 400) unless $q;

        $set = schema('netdisco')->resultset('Device')->search_fuzzy($q);
    }
    return unless $set->count;

    content_type('text/html');
    template 'ajax/search/device.tt', {
      results => $set,
    }, { layout => undef };
};

true;
