package App::Netdisco::Web::Plugin::AdminTask::UserLog;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_admin_task({
  tag => 'userlog',
  label => 'User Activity Log',
});

ajax '/ajax/control/admin/userlog/del' => require_role admin => sub {
    send_error('Missing entry', 400) unless param('entry');

    schema('netdisco')->txn_do(sub {
      my $device = schema('netdisco')->resultset('UserLog')
        ->search({entry => param('entry')})->delete;
    });
};

ajax '/ajax/control/admin/userlog/delall' => require_role admin => sub {
    schema('netdisco')->txn_do(sub {
      my $device = schema('netdisco')->resultset('UserLog')->delete;
    });
};

ajax '/ajax/content/admin/userlog' => require_role admin => sub {
    my $set = schema('netdisco')->resultset('UserLog')
      ->search({}, {
        order_by => { -desc => [qw/creation event/] },
        rows => 200,
      });

    content_type('text/html');
    template 'ajax/admintask/userlog.tt', {
      results => $set,
    }, { layout => undef };
};

true;
