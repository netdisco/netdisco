package App::Netdisco::Web::Plugin::Device::Modules;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_device_tab({ tag => 'modules', label => 'Modules' });

ajax '/ajax/content/device/:thing' => require_login sub {
    return "<p>Hello, this is where the ". param('thing') ." content goes.</p>";
};

true;
