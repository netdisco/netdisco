package App::Netdisco::Worker::Plugin::Discover::Hooks;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Worker;

register_worker({ phase => 'late' }, sub {
  my ($job, $workerconf) = @_;

  my @hooks = ('discover');
  push @hooks, 'new_device' if vars->{'new_device'};

  my $count = queue_hooks(@hooks);
  return Status->info(sprintf ' [%s] hooks - %d queued', $job->device, $count);
});

true;
