package App::Netdisco::Worker::Plugin::Noop;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  return Status->done('no-op completed OK.');
});

true;
