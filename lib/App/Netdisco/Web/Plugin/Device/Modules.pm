package App::Netdisco::Web::Plugin::Device::Modules;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Util::Web (); # for sort_module
use App::Netdisco::Web::Plugin;

register_device_tab({ tag => 'modules', label => 'Modules' });

ajax '/ajax/content/device/modules' => require_login sub {
    my $q = param('q');

    my $device = schema('netdisco')->resultset('Device')
      ->search_for_device($q) or send_error('Bad device', 400);
    my @set = $device->modules->search({}, {order_by => { -asc => [qw/parent class pos index/] }});

    # sort modules (empty set would be a 'no records' msg)
    my $results = &App::Netdisco::Util::Web::sort_modules( \@set );
    return unless scalar %$results;

    content_type('text/html');
    template 'ajax/device/modules.tt', {
      nodes => $results,
    }, { layout => undef };
};

true;
