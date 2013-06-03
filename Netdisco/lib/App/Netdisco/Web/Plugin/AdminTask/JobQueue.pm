package App::Netdisco::Web::Plugin::AdminTask::JobQueue;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use App::Netdisco::Web::Plugin;

register_admin_task({
  tag => 'jobqueue',
  label => 'Job Queue',
});

ajax '/ajax/control/admin/jobqueue/del' => sub {
    send_error('Forbidden', 403) unless var('user')->admin;
    send_error('Missing job', 400) unless length param('job');

    schema('netdisco')->txn_do(sub {
      my $device = schema('netdisco')->resultset('Admin')
        ->search({job => param('job')})->delete;
    });
};

ajax '/ajax/content/admin/jobqueue' => sub {
    send_error('Forbidden', 403) unless var('user')->admin;

    my $set = schema('netdisco')->resultset('Admin')
      ->with_times
      ->search({}, {order_by => { -desc => [qw/entered device action/] }});

    content_type('text/html');
    template 'ajax/admintask/jobqueue.tt', {
      results => $set,
    }, { layout => undef };
};

true;
