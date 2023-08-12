package App::Netdisco::Worker::Plugin::Internal::SNMPFastDiscover;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Scalar::Util 'blessed';

register_worker({ phase => 'check', driver => 'direct' }, sub {
  my ($job, $workerconf) = @_;

  # if the job is a queued job, and discover, and the first one...
  if ($job->job and $job->action eq 'discover' and not $job->log
      and (not blessed $job->device or not $job->device->in_storage)) {

      config->{'snmp_try_slow_connect'} = false;
      debug "running with fast SNMP timeouts for initial discover";
  }

  debug "running with configured SNMP timeouts";
});

true;
