package App::NetdiscoX::Web::Plugin::ObserviumSparklines;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;

use App::Netdisco::Web::Plugin;

use File::ShareDir 'dist_dir';
use Path::Class;

register_device_port_column({
  name  => 'observiumsparklines',
  position => 'mid',
  label => 'Traffic',
  default => 'on',
});

register_css('observiumsparklines');
register_javascript('observiumsparklines');

true;
