package App::Netdisco::Worker::Plugin::Monitor;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::NodeMonitor ();

register_worker({ stage => 'check' }, sub {
  return Status->done('Monitor is able to run');
});

register_worker({ stage => 'main' }, sub {
  my ($job, $workerconf) = @_;
  App::Netdisco::Util::NodeMonitor::monitor();
  return Status->done('Generated monitor data');
});

true;
