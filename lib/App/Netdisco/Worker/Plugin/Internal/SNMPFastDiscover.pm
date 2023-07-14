package App::Netdisco::Worker::Plugin::Internal::SNMPFastDiscover;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

register_worker({ phase => 'check', driver => 'direct' }, sub {
  my ($job, $workerconf) = @_;

  # if the job is a queued job, and discover, and the first one...
  if ($job->job and $job->action eq 'discover' and not $job->log) {
      config->{'snmp_try_slow_connect'} = false;
      debug sprintf '[%s] skipping long SNMP timeouts for initial discover',
        $job->device;
  }
});

true;
