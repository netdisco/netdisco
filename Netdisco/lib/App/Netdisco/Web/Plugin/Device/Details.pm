package App::Netdisco::Web::Plugin::Device::Details;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_device_tab({ tag => 'details', label => 'Details' });

# device details table
ajax '/ajax/content/device/details' => require_login sub {
    my $q = param('q');
    my $device = schema('netdisco')->resultset('Device')
      ->search_for_device($q) or send_error('Bad device', 400);

    my $results
        = schema('netdisco')->resultset('Device')
        ->search( { 'me.ip' => $device->ip } )->with_times()
        ->with_poestats_as_hashref;

    content_type('text/html');
    template 'ajax/device/details.tt', {
      d => $results->[0],
    }, { layout => undef };
};

true;
