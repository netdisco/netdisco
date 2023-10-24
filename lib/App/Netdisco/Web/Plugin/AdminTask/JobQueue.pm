package App::Netdisco::Web::Plugin::AdminTask::JobQueue;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::JobQueue qw/jq_log jq_delete/;

register_admin_task({
  tag => 'jobqueue',
  label => 'Job Queue',
});

ajax '/ajax/control/admin/jobqueue/del' => require_role admin => sub {
    send_error('Missing job', 400) unless param('job');
    jq_delete( param('job') );
};

ajax '/ajax/control/admin/jobqueue/delall' => require_role admin => sub {
    jq_delete();
};

sub commify {
    my $text = reverse $_[0];
    $text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
    return scalar reverse $text;
}

ajax '/ajax/content/admin/jobqueue' => require_role admin => sub {
    content_type('text/html');

    my $jq_total = schema(vars->{'tenant'})->resultset('Admin')->count();
    my $jq_queued = schema(vars->{'tenant'})->resultset('Admin')->search({status => 'queued'})->count();
    my $jq_running = schema(vars->{'tenant'})->resultset('Admin')->search({status => { -like =>  'queued-%'}})->count();
    my $jq_done = schema(vars->{'tenant'})->resultset('Admin')->search({status => 'done'})->count();
    my $jq_errored = schema(vars->{'tenant'})->resultset('Admin')->search({status => 'error'})->count();

    template 'ajax/admintask/jobqueue.tt', {
      jq_total => commify($jq_total || 0),
      jq_queued => commify($jq_queued || 0),
      jq_running => commify($jq_running || 0),
      jq_done => commify($jq_done || 0),
      jq_errored => commify($jq_errored || 0),
      results => [ jq_log ],
    }, { layout => undef };
};

true;
