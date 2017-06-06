package App::Netdisco::Web::Plugin::AdminTask::TimedOutDevices;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::DNS 'hostnames_resolve_async';

register_admin_task({
  tag => 'timedoutdevices',
  label => 'SNMP Connect Failures',
});

ajax '/ajax/content/admin/timedoutdevices' => require_role admin => sub {
    my @set = schema('netdisco')->resultset('DeviceSkip')->search({
      deferrals => { '>' => 0 }
    },{ rows => (setting('dns')->{max_outstanding} || 50), order_by =>
      [{ -desc => 'deferrals' }, { -asc => [qw/device backend/] }]
    })->hri->all;

    my $results = hostnames_resolve_async(\@set, [2,2,2]);

    content_type('text/html');
    template 'ajax/admintask/timedoutdevices.tt', {
      results => $results
    }, { layout => undef };
};

true;
