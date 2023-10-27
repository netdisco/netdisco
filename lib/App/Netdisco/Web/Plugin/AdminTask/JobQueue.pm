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

    my @backends = schema(vars->{'tenant'})->resultset('DeviceSkip')
        ->search({device => '255.255.255.255'})->hri->all;

    my $num_backends = scalar keys @backends;
    my $tot_workers  = 0;
    $tot_workers += $_->{deferrals} for @backends;

    my $jq_locked = schema(vars->{'tenant'})->resultset('Admin')
      ->search({status => 'queued', backend => { '!=' => undef }})->count();

    my $jq_backlog = schema(vars->{'tenant'})->resultset('Admin')
      ->search({status => 'queued', backend => undef })->count();

    my $jq_done = schema(vars->{'tenant'})->resultset('Admin')
      ->search({status => 'done'})->count();

    my $jq_errored = schema(vars->{'tenant'})->resultset('Admin')
      ->search({status => 'error'})->count();

    my $jq_stale = schema(vars->{'tenant'})->resultset('Admin')->search({
        status => 'queued',
        backend => { '!=' => undef },
        started => \[q/<= (LOCALTIMESTAMP - ?::interval)/, setting('jobs_stale_after')],
    })->count();

    my $jq_total = schema(vars->{'tenant'})->resultset('Admin')->count();

    template 'ajax/admintask/jobqueue.tt', {
      num_backends => commify($num_backends || '?'),
      tot_workers  => commify($tot_workers || '?'),

      jq_running => commify($jq_locked - $jq_stale),
      jq_backlog => commify($jq_backlog),
      jq_done => commify($jq_done),
      jq_errored => commify($jq_errored),
      jq_stale => commify($jq_stale),
      jq_total => commify($jq_total),

      results => [ jq_log ],
    }, { layout => undef };
};

true;
