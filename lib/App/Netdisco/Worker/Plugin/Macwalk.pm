package App::Netdisco::Worker::Plugin::Macwalk;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::JobQueue 'jq_insert';
use Dancer::Plugin::DBIC 'schema';

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;

  my @walk = schema(vars->{'tenant'})->resultset('Virtual::WalkJobs')
    ->search(undef,{ bind => [
      'macsuck', 'macsuck',
      setting('workers')->{'max_deferrals'},
      setting('workers')->{'retry_after'},
    ]})->get_column('ip')->all;

  jq_insert([
    map {{
      device => $_,
      action => 'macsuck',
      username => $job->username,
      userip => $job->userip,
    }} (@walk)
  ]);

  return Status->done('Queued macsuck job for all devices');
});

true;
