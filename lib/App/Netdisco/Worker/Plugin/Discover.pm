package App::Netdisco::Worker::Plugin::Discover;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device 'is_discoverable_now';
use Time::HiRes 'gettimeofday';

register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  return Status->error('discover failed: unable to interpret device param')
    unless defined $device;

  return Status->error("discover failed: no device param (need -d ?)")
    if $device->ip eq '0.0.0.0';

  return Status->info("discover skipped: $device is not discoverable")
    unless is_discoverable_now($device);

  # would be possible just to use LOCALTIMESTAMP on updated records, but by using this
  # same value for them all, we can if we want add a job at the end to
  # select and do something with the updated set (see set archive, below)
  vars->{'timestamp'} = ($job->is_offline and $job->entered)
    ? (schema('netdisco')->storage->dbh->quote($job->entered) .'::timestamp')
    : 'to_timestamp('. (join '.', gettimeofday) .')::timestamp';

  return Status->done('Discover is able to run.');
});

true;
