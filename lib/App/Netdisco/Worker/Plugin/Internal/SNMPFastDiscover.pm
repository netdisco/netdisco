package App::Netdisco::Worker::Plugin::Internal::SNMPFastDiscover;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Scalar::Util 'blessed';

register_worker({ phase => 'check', driver => 'direct' }, sub {
  my ($job, $workerconf) = @_;

  my $params = $job->params;

  if ($params->{snmptimeout}) {
      config->{'snmptimeout'} = $params->{snmptimeout};
      debug sprintf "using per-job snmptimeout: %s", $params->{snmptimeout};
  }

  if ($params->{snmpretries}) {
      config->{'snmpretries'} = $params->{snmpretries};
      debug sprintf "using per-job snmpretries: %s", $params->{snmpretries};
  }

  if ($params->{bulkwalk_repeaters}) {
      config->{'bulkwalk_repeaters'} = $params->{bulkwalk_repeaters};
      debug sprintf "using per-job bulkwalk_repeaters: %s", $params->{bulkwalk_repeaters};
  }

  # if the job is a queued job, and discover, and the first one...
  if ($job->job and $job->action eq 'discover' and not $job->log
      and (not blessed $job->device or not $job->device->in_storage)) {

      config->{'snmp_try_slow_connect'} = false;
      debug "running with fast SNMP timeouts for initial discover";
  }
  else {
      debug "running with configured SNMP timeouts" unless $params->{snmptimeout};
  }
});

true;
