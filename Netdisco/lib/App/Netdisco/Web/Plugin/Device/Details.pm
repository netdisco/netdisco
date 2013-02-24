package App::Netdisco::Web::Plugin::Device::Details;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use App::Netdisco::Web::Plugin;

register_device_tab({ id => 'details', label => 'Details' });

# device details table
ajax '/ajax/content/device/details' => sub {
    my $q = param('q');
    my $device = schema('netdisco')->resultset('Device')
      ->with_times()->search_for_device($q) or return;

    content_type('text/html');
    template 'ajax/device/details.tt', {
      d => $device,
    }, { layout => undef };
};

true;
