package App::Netdisco::Web::Plugin::AdminTask::PollerPerformance;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_admin_task({
  tag => 'performance',
  label => 'Poller Performance',
});

ajax '/ajax/content/admin/performance' => require_role admin => sub {
    my $set = schema('netdisco')->resultset('Virtual::PollerPerformance');

    content_type('text/html');
    template 'ajax/admintask/performance.tt', {
      results => $set,
    }, { layout => undef };
};

true;
