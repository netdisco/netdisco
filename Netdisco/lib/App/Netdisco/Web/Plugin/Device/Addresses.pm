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

    my $set = $device->device_ips->search( {}, { order_by => 'alias' } );
    return unless $set->count;

    if (request->is_ajax) {
        template 'ajax/device/addresses.tt', { results => $set, },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/device/addresses_csv.tt', { results => $set, },
            { layout => undef };
    }
};

true;
