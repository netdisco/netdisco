package App::Netdisco::Worker::Runner;

use Dancer ':moose :syntax';
use Dancer::Factory::Hook;

use App::Netdisco::Worker;
use aliased 'App::Netdisco::Worker::Status';

use Try::Tiny;
use Role::Tiny;
use namespace::clean;

# mixin code to run workers loaded via plugins
sub run {
  my ($self, $job) = @_;
  die 'bad job to run()' unless ref $job eq 'App::Netdisco::Backend::Job';

  my $action = $job->action;
  my @phase_hooks = grep { m/^nd2worker_${action}_/ }
                         @{ (setting('_nd2worker_hooks') || []) };

  # run 00init primary
  my $status = _run_first("nd2worker_${action}_00init_primary", $job);
  return $status if $status->not_ok;

  # run each 00init worker
  _run_all("nd2worker_${action}_00init", $job);

  # run primary
  _run_first($_.'_primary', $job) for (@phase_hooks);

  # run each worker
  _run_all($_, $job) for (@phase_hooks);

  return true;
}

sub _run_first {
  my $hook = shift or return Status->error('missing hook param');
  my $job  = shift or return Status->error('missing job param');

  my $store = Dancer::Factory::Hook->instance();
  $store->hook_is_registered($hook)
    or return Status->error("no such hook: $hook");

  foreach my $worker (@{ $store->get_hooks_for($hook) }) {
    my $retval = false;
    try {
      $retval = $worker->($job);
    }
    catch {
      $retval = Status->error($_);
    };

    $retval ||= Status->done('no status supplied');
    return $retval if $retval->ok;
  }

  return Status->error('no worker was successful');
}

true;
