package App::Netdisco::Worker::Plugin::DiscoverAll;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::JobQueue 'jq_insert';
use Dancer::Plugin::DBIC 'schema';

register_worker({ phase => 'check' }, sub {
  return Status->defer("discoverall skipped: have not yet primed skiplist")
    unless schema(vars->{'tenant'})->resultset('DeviceSkip')
      ->search({
        backend => setting('workers')->{'BACKEND'},
        device  => '255.255.255.255',
      })->count();

  return Status->done('Discoverall is able to run');
});

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;

  my @walk = schema(vars->{'tenant'})->resultset('Virtual::WalkJobs')
    ->search(undef,{ bind => [
      'discover', 'discover',
      setting('workers')->{'max_deferrals'},
      setting('workers')->{'retry_after'},
    ]})->get_column('ip')->all;

  jq_insert([
    map {{
      device => $_,
      action => 'discover',
      username => $job->username,
      userip => $job->userip,
    }} (@walk)
  ]);

  return Status->done('Queued discover job for all devices');
});

true;
