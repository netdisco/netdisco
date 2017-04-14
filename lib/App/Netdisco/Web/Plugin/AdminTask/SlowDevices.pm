package App::Netdisco::Web::Plugin::AdminTask::SlowDevices;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_admin_task({
  tag => 'slowdevices',
  label => 'Slowest Devices',
});

ajax '/ajax/content/admin/slowdevices' => require_role admin => sub {
    my $set = schema('netdisco')->resultset('Virtual::SlowDevices');

    content_type('text/html');
    template 'ajax/admintask/slowdevices.tt', {
      results => $set,
    }, { layout => undef };
};

true;
