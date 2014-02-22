package App::Netdisco::Web::Plugin::AdminTask::JobQueue;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_admin_task({
  tag => 'jobqueue',
  label => 'Job Queue',
});

ajax '/ajax/control/admin/jobqueue/del' => require_role admin => sub {
    send_error('Missing job', 400) unless param('job');

    schema('netdisco')->txn_do(sub {
      my $device = schema('netdisco')->resultset('Admin')
        ->search({job => param('job')})->delete;
    });
};

ajax '/ajax/control/admin/jobqueue/delall' => require_role admin => sub {
    schema('netdisco')->txn_do(sub {
      my $device = schema('netdisco')->resultset('Admin')->delete;
    });
};

ajax '/ajax/content/admin/jobqueue' => require_role admin => sub {
    my $set = schema('netdisco')->resultset('Admin')
      ->with_times
      ->search({}, {
        order_by => { -desc => [qw/entered device action/] },
        rows => 50,
      });

    content_type('text/html');
    template 'ajax/admintask/jobqueue.tt', {
      results => $set,
    }, { layout => undef };
};

true;
