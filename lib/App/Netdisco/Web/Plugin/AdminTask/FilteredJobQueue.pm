package App::Netdisco::Web::Plugin::AdminTask::FilteredJobQueue;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::JobQueue qw/jq_log jq_delete/;

register_admin_task({
  tag => 'filteredjobqueue',
  label => 'Filtered Job Queue',
});

ajax '/ajax/control/admin/filteredjobqueue/del' => require_role admin => sub {
    send_error('Missing job', 400) unless param('job');
    jq_delete( param('job') );
};

ajax '/ajax/control/admin/filteredjobqueue/delall' => require_role admin => sub {
    jq_delete();
};

ajax '/ajax/content/admin/filteredjobqueue' => require_role admin => sub {
    content_type('text/html');

    template 'ajax/admintask/filteredjobqueue.tt', {
      results => [ jq_log ],
    }, { layout => undef };
};

true;
