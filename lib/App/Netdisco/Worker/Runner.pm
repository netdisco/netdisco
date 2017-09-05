package App::Netdisco::Worker::Runner;

use Dancer qw/:moose :syntax/;
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

  my @newuserconf = ();
  my @userconf = @{ setting('device_auth') || [] };

  # reduce device_auth by only/no
  if (ref $job->device) {
    foreach my $stanza (@userconf) {
      my $no   = (exists $stanza->{no}   ? $stanza->{no}   : undef);
      my $only = (exists $stanza->{only} ? $stanza->{only} : undef);

      next if $no and check_acl_no($job->device->ip, $no);
      next if $only and not check_acl_only($job->device->ip, $only);

      push @newuserconf, $stanza;
    }
  }

  # per-device action but no device creds available
  return Status->error('skipped with no device creds')
    if ref $job->device and 0 == scalar @newuserconf;

  # back up and restore device_auth
  my $guard = guard { set(device_auth => \@userconf) };
  set(device_auth => \@newuserconf);

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

  # track returned status of the workers
  my $best = Status->error("no primary worker at $hook was successful");

  foreach my $worker (@{ $store->get_hooks_for($hook) }) {
    try {
      my $retval = $worker->($job);
      # could die or return undef or a scalar or Status or another class
      $best = $retval if ref $retval eq 'App::Netdisco::Worker::Status';
    }
    catch { $best->log($_) };

    last if $best->is_ok;
  }

  return $best;
}

sub _run_all {
  my $hook = shift or return Status->error('missing hook param');
  my $job  = shift or return Status->error('missing job param');

  my $store = Dancer::Factory::Hook->instance();
  $store->hook_is_registered($hook)
    or return Status->error("no such hook: $hook");

  foreach my $worker (@{ $store->get_hooks_for($hook) }) {
    try { $worker->($job) };
  }
}

true;
