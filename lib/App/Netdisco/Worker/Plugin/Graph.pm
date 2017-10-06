package App::Netdisco::Worker::Plugin::Graph;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Graph ();

register_worker({ stage => 'check' }, sub {
  return Status->done('Graph is able to run');
});

register_worker({ stage => 'main' }, sub {
  App::Netdisco::Util::Graph::graph();
  return Status->done('Generated graph data');
});

true;
