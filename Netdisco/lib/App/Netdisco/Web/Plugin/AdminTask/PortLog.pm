package App::Netdisco::Web::Plugin::AdminTask::PortLog;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_admin_task({
  tag => 'portlog',
  label => 'Port Control Log',
  hidden => true,
});

ajax '/ajax/content/admin/portlog' => require_role admin => sub {
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
      });

    content_type('text/html');
    template 'ajax/admintask/portlog.tt', {
      results => $set,
    }, { layout => undef };
};

true;
