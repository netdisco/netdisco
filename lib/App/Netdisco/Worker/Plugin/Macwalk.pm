package App::Netdisco::Worker::Plugin::Macwalk;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::JobQueue qw/jq_queued jq_insert/;
use Dancer::Plugin::DBIC 'schema';

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;

  my %queued = map {$_ => 1} jq_queued('macsuck');
  my @devices = schema('netdisco')->resultset('Device')
    ->has_layer('2')->get_column('ip')->all;
  my @filtered_devices = grep {!exists $queued{$_}} @devices;

  jq_insert([
    map {{
      device => $_,
      action => 'macsuck',
      username => $job->username,
      userip => $job->userip,
    }} (@filtered_devices)
  ]);

  return Status->done('Queued macsuck job for all devices');
});

true;
