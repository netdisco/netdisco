package App::Netdisco::Web::Plugin::Report::PortLog;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report({
  tag => 'portlog',
  label => 'Port Control Log',
  category => 'Port', # not used
  hidden => true,
});

ajax '/ajax/content/report/portlog' => require_role port_control => sub {
    my $device = param('q');
    my $port = param('f');
    send_error('Bad Request', 400) unless $device and $port;

    $device = schema('netdisco')->resultset('Device')
      ->search_for_device($device);
    return unless $device;

    my $set = schema('netdisco')->resultset('DevicePortLog')->search({
        ip => $device->ip,
        port => $port,
      }, {
        order_by => { -desc => [qw/creation/] },
        rows => 200,
      })->with_times;

    content_type('text/html');
    template 'ajax/report/portlog.tt', {
      results => $set,
    }, { layout => undef };
};

true;
