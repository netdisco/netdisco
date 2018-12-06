package App::Netdisco::Worker::Plugin::NodeMonitor;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::NodeMonitor ();

register_worker({ phase => 'main' }, sub {
  App::Netdisco::Util::NodeMonitor::monitor();
  return Status->done('Generated monitor data');
});

true;
