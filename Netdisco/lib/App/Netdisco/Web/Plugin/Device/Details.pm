package App::Netdisco::Web::Plugin::Device::Details;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use NetAddr::IP::Lite ':lower';

use App::Netdisco::Web::Plugin;

register_device_tab({ id => 'details', label => 'Details' });

# device details table
ajax '/ajax/content/device/details' => sub {
    my $ip = NetAddr::IP::Lite->new(param('q'));
    return unless $ip;

    my $device = schema('netdisco')->resultset('Device')
                   ->with_times()->find($ip->addr);
    return unless $device;

    content_type('text/html');
    template 'ajax/device/details.tt', {
      d => $device,
    }, { layout => undef };
};

true;
