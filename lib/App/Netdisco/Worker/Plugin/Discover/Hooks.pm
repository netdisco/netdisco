package App::Netdisco::Worker::Plugin::Discover::Hooks;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::JobQueue 'jq_insert';

register_worker({ phase => 'late' }, sub {
  my ($job, $workerconf) = @_;
  return unless vars->{'new_device'}
    and vars->{'hook_data'};

  # TODO inspect hooks config and queue if needed

  jq_insert({
    action => 'hook::http',
    extra  => to_json( vars->{'hook_data'} || {} ),
  });

  return Status->info(sprintf 'Queued new_device Hook for %s.', $job->device);
});

true;
