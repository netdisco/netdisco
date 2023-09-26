package App::Netdisco::Worker::Plugin::Scheduler;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::JobQueue 'jq_insert';
use Dancer::Plugin::DBIC 'schema';

use JSON::PP ();

register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;

  return Status->error("Missing data of Scheduler entry")
    unless $job->extra;

  return Status->defer("scheduler skipped: have not yet primed skiplist")
    unless schema(vars->{'tenant'})->resultset('DeviceSkip')
      ->search({
        backend => setting('workers')->{'BACKEND'},
        device  => '255.255.255.255',
      })->count();

  return Status->done('Scheduler is able to run');
});

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;

  my $coder = JSON::PP->new->utf8(0)->allow_nonref(1)->allow_unknown(1);
  my $sched = $coder->decode( $job->extra || {} );
  my $action = $sched->{action} || $sched->{label};

  return Status->error("Missing label of Scheduler entry")
    unless $action;

  my @walk = schema(vars->{'tenant'})->resultset('Virtual::WalkJobs')
    ->search(undef,{ bind => [
      $action, ('scheduled-'. $sched->{label}),
      setting('workers')->{'max_deferrals'},
      setting('workers')->{'retry_after'},
    ]})->get_column('ip')->all;

  jq_insert([
    map {{
      device => $_,
      action => $action,
      port      => $sched->{port},
      subaction => $sched->{subaction},
      username => $job->username,
      userip   => $job->userip,
    }} (@walk)
  ]);

  return Status->done(sprintf 'Queued %s job for all devices', $action);
});

true;
