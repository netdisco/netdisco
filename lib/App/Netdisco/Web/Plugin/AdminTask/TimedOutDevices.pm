package App::Netdisco::Web::Plugin::AdminTask::TimedOutDevices;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_admin_task({
  tag => 'timedoutdevices',
  label => 'SNMP Connect Failures',
});

ajax '/ajax/content/admin/timedoutdevices' => require_role admin => sub {
    my @results = schema('netdisco')->resultset('DeviceSkip')->search({
      deferrals => { '>' => 0 }
    },{ order_by =>
      [{ -desc => 'deferrals' }, { -asc => [qw/device backend/] }]
    })->hri->all;

    content_type('text/html');
    template 'ajax/admintask/timedoutdevices.tt', {
      results => \@results,
    }, { layout => undef };
};

true;
