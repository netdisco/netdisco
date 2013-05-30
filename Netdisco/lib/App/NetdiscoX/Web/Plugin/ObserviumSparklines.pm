package App::NetdiscoX::Web::Plugin::ObserviumSparklines;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;

use App::Netdisco::Web::Plugin;

register_device_port_column({
  name  => 'c_observiumsparklines',
  position => 'mid',
  label => 'Traffic',
  default => 'on',
});

true;
