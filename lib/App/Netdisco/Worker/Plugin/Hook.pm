package App::Netdisco::Worker::Plugin::Hook;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;

  return Status->error('can only run a specific hook')
    unless $job->action eq 'hook' and defined $job->only_namespace;

  return Status->done('Hook is able to run.');
});

true;
