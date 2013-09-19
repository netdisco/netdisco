package App::Netdisco::Web::Plugin::Search::Device;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use List::MoreUtils ();

use App::Netdisco::Web::Plugin;

register_search_tab({ tag => 'device', label => 'Device' });

my $headers = ['Device','Contact','Location','System Name','Model','OS Version','Management IP','Serial'];

# device with various properties or a default match-all
sub get_rs_device {
    my $q = shift;
    my $has_opt = shift;

    my $set;

    if ($has_opt) {
        $set = schema('netdisco')->resultset('Device')->search_by_field(scalar params);
    }
    else {
        send_error('Missing query', 400) unless $q;

        $set = schema('netdisco')->resultset('Device')->search_fuzzy($q);
    }
    return $set;
}

ajax '/ajax/content/search/device' => require_login sub {
    my $q = param('q');
    my $has_opt = List::MoreUtils::any {param($_)}
      qw/name location dns ip description model os_ver vendor/;
    
    unless ($has_opt || $q) {
        send_error('Missing query', 400)
    }

    my $set = get_rs_device($q, $has_opt);

    return unless $set->count;

    content_type('text/html');
    template 'ajax/search/device.tt', {
      results => $set,
    }, { layout => undef };
};

get '/search/device' => require_login sub {
    my $q = param('q');
    my $format = param('format');
    my $has_opt = List::MoreUtils::any {param($_)}
      qw/name location dns ip description model os_ver vendor/;
    
    unless ($has_opt || $q) {
        send_error('Missing query', 400)
    }

    my $set = get_rs_device($q, $has_opt);

    return unless $set->count;

    if ( $format eq 'csv' ) {
        
        header( 'Content-Type' => 'text/comma-separated-values' );
        header( 'Content-Disposition' =>
                "attachment; filename=\"nd-devicesearch.csv\"" );
        template 'ajax/search/device_csv.tt', {
      results => $set,
      headers => $headers,
    }, { layout => undef };
    }
    else {
        return;
    }
};

true;
