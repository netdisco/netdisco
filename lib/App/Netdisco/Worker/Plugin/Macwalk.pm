package App::Netdisco::Worker::Plugin::Macwalk;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::JobQueue qw/jq_queued jq_insert/;
use Dancer::Plugin::DBIC 'schema';

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;

  my @backends = schema('netdisco')->resultset('DeviceSkip')
                                   ->get_distinct_col('backend');

  # TODO what if DeviceSkip table is empty

  my @devices = ();
  foreach my $host (@backends) {
      push @devices,
      schema('netdisco')->resultset('Device')
        ->skipped(
          'macsuck', $host,
          setting('workers')->{'max_deferrals'},
          setting('workers')->{'retry_after'}
        )
        ->search({ 'skipped_actions.device' => undef})
        ->get_column('ip')->all;
  }

  my %queued = map {$_ => 1} jq_queued('macsuck');
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
