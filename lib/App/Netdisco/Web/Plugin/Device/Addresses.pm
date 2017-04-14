package App::Netdisco::Web::Plugin::Device::Addresses;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_device_tab( { tag => 'addresses', label => 'Addresses', provides_csv => 1 } );

# device interface addresses
get '/ajax/content/device/addresses' => require_login sub {
    my $q = param('q');

    my $device
        = schema('netdisco')->resultset('Device')->search_for_device($q)
        or send_error( 'Bad device', 400 );

    my @results = $device->device_ips->search( {}, { order_by => 'alias' } )->hri->all;

    return unless scalar @results;

    if (request->is_ajax) {
        my $json = to_json( \@results );
        template 'ajax/device/addresses.tt', { results => $json },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/device/addresses_csv.tt', { results => \@results },
            { layout => undef };
    }
};

1;
