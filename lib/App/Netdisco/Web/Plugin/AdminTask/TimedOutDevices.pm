package App::Netdisco::Web::Plugin::AdminTask::TimedOutDevices;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::FastResolver 'hostnames_resolve_async';

register_admin_task({
  tag => 'timedoutdevices',
  label => 'SNMP Connect Failures',
});

ajax '/ajax/control/admin/timedoutdevices/del' => require_role admin => sub {
    send_error('Missing backend', 400) unless param('backend');
    send_error('Missing device',  400) unless param('device');

    schema('netdisco')->resultset('DeviceSkip')->find_or_create({
      backend => param('backend'), device => param('device'),
    },{ key => 'device_skip_pkey' })->update({ deferrals => 0 });
};

ajax '/ajax/content/admin/timedoutdevices' => require_role admin => sub {
    my @set = schema('netdisco')->resultset('DeviceSkip')->search({
      deferrals => { '>' => 0 }
    },{ rows => (setting('dns')->{max_outstanding} || 50), order_by =>
      [{ -desc => 'deferrals' }, { -asc => [qw/device backend/] }]
    })->hri->all;

    foreach my $row (@set) {
      next unless defined $row->{last_defer};
      $row->{last_defer} =~ s/\.\d+//;
    }
    my $results = hostnames_resolve_async(\@set, [2]);

    content_type('text/html');
    template 'ajax/admintask/timedoutdevices.tt', {
      results => $results
    }, { layout => undef };
};

true;
