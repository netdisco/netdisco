package App::NetdiscoX::Web::Plugin::Observium;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;

use App::Netdisco::Web::Plugin;

use File::ShareDir 'dist_dir';
use Path::Class;

register_device_port_column({
  name  => 'observium',
  position => 'mid',
  label => 'Traffic',
  default => 'on',
});

register_css('observium');
register_javascript('observium');

true;
