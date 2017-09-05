package App::Netdisco::Worker::Runner;

use Dancer qw/:moose :syntax/;
use Dancer::Factory::Hook;

use App::Netdisco::Worker;
use aliased 'App::Netdisco::Worker::Status';

use Try::Tiny;
use Moo::Role;
use Scope::Guard 'guard';
use namespace::clean;

has 'job' => (
  is => 'rw',
);

has 'jobstat' => (
  is => 'rw',
  default => sub { Status->error("no worker was successful") },
);

after 'run', 'run_workers' => sub {
  my $self = shift;
  $self->jobstat->update_job($self->job);
};

# mixin code to run workers loaded via plugins
sub run {
  my $self = shift;

  $self->job(shift) if scalar @_;
  die 'bad job to run()'
    unless ref $self->job eq 'App::Netdisco::Backend::Job';

  my @newuserconf = ();
  my @userconf = @{ setting('device_auth') || [] };

  # reduce device_auth by only/no
  if (ref $self->job->device) {
    foreach my $stanza (@userconf) {
      my $no   = (exists $stanza->{no}   ? $stanza->{no}   : undef);
      my $only = (exists $stanza->{only} ? $stanza->{only} : undef);

      next if $no and check_acl_no($self->job->device->ip, $no);
      next if $only and not check_acl_only($self->job->device->ip, $only);

      push @newuserconf, $stanza;
    }
  }

  # per-device action but no device creds available
  return $self->jobstat->error('skipped with no device creds')
    if ref $self->job->device and 0 == scalar @newuserconf;

  # back up and restore device_auth
  my $guard = guard { set(device_auth => \@userconf) };
  set(device_auth => \@newuserconf);

  my $action = $self->job->action;
  my @phase_hooks = grep { m/^nd2worker_${action}_/ }
                         @{ (setting('_nd2worker_hooks') || []) };

  # run 00init primary
  $self->run_workers("nd2worker_${action}_00init_primary");
  return $self->jobstat if $self->jobstat->not_ok;

  # run each 00init worker
  $self->run_workers("nd2worker_${action}_00init");

  # run primary
  $self->run_workers("${_}_primary") for (@phase_hooks);

  # run each worker
  $self->run_workers($_) for (@phase_hooks);

  return $self->jobstat;
}

sub run_workers {
  my $self = shift;
  my $hook = shift or return $self->jobstat->error('missing hook param');

  my $store = Dancer::Factory::Hook->instance();
  $store->hook_is_registered($hook)
    or return Status->error("no such hook: $hook");

  foreach my $worker (@{ $store->get_hooks_for($hook) }) {
    try {
      my $retval = $worker->($self->job);
      # could die or return undef or a scalar or Status or another class
      $self->jobstat($retval) if ref $retval eq 'App::Netdisco::Worker::Status';
    }
    catch { $self->jobstat->log($_) };

    last if $hook =~ m/_primary$/ and $self->jobstat->is_ok;
  }
}

true;
