package App::Netdisco::Worker::Plugin::DiscoverAll;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::JobQueue qw/jq_queued jq_insert/;
use Dancer::Plugin::DBIC 'schema';

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;

  my %queued = map {$_ => 1} jq_queued('discover');
  my @devices = schema('netdisco')->resultset('Device')->search({
    -or => [ 'vendor' => undef, 'vendor' => { '!=' => 'netdisco' }],
  })->get_column('ip')->all;
  my @filtered_devices = grep {!exists $queued{$_}} @devices;

  jq_insert([
    map {{
      device => $_,
      action => 'discover',
      username => $job->username,
      userip => $job->userip,
    }} (@filtered_devices)
  ]);

  return Status->done('Queued discover job for all devices');
});

true;
