package App::Netdisco::Worker::Plugin::Scheduler;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::JobQueue 'jq_insert';
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::Permission qw/acl_matches acl_matches_only/;
use NetAddr::IP;
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
      '', 0,
    ]})->get_column('ip')->all;

  # the skip list behind WalkJobs is primed from the schedule each backend
  # has in its own configuration, and NETDISCO_NO_SCHEDULER removes it from
  # the workers, so the entry's device, only and no are applied here too
  my $net = ($sched->{device} ? NetAddr::IP->new($sched->{device}) : undef);
  undef $net if $net and ($net->num == 0 or $net->addr eq '0.0.0.0');

  if ($net or $sched->{only} or $sched->{no}) {
    my %device = map {($_->ip => $_)}
      schema(vars->{'tenant'})->resultset('Device')->all;

    @walk = grep {
      my $d = $device{$_};
      $d
      and (not $net or acl_matches_only($d, $net->cidr))
      and (not $sched->{only} or acl_matches_only($d, $sched->{only}))
      and (not $sched->{no} or not acl_matches($d, $sched->{no}))
    } @walk;
  }

  jq_insert([
    map {{
      device => $_,
      action => $action,
      port      => $sched->{port},
      subaction => ($sched->{extra} || $sched->{subaction}),
      username => $job->username,
      userip   => $job->userip,
    }} (@walk)
  ]);

  return Status->done(sprintf 'Queued %s job for all devices', $action);
});

true;
