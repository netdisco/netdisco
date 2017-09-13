package App::Netdisco::Worker::Plugin::Graph;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Graph ();

register_worker({ stage => 'check' }, sub {
  my ($job, $workerconf) = @_;
  App::Netdisco::Util::Graph::graph();
  return Status->done('Generated graph data.');
});

true;
