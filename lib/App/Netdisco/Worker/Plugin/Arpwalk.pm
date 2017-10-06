package App::Netdisco::Worker::Plugin::Arpwalk;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::JobQueue qw/jq_queued jq_insert/;
use Dancer::Plugin::DBIC 'schema';

register_worker({ stage => 'check' }, sub {
  return Status->done('Arpwalk is able to run');
});

register_worker({ stage => 'main' }, sub {
  my ($job, $workerconf) = @_;

  my %queued = map {$_ => 1} jq_queued('arpnip');
  my @devices = schema('netdisco')->resultset('Device')->search({
    -or => [ 'vendor' => undef, 'vendor' => { '!=' => 'netdisco' }],
  })->has_layer('3')->get_column('ip')->all;
  my @filtered_devices = grep {!exists $queued{$_}} @devices;

  jq_insert([
    map {{
      device => $_,
      action => 'arpnip',
      username => $job->username,
      userip => $job->userip,
    }} (@filtered_devices)
  ]);

  return Status->done('Queued arpnip job for all devices');
});

true;
