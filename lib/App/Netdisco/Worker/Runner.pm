package App::Netdisco::Worker::Runner;

use Dancer qw/:moose :syntax/;
use Dancer::Factory::Hook;
use aliased 'App::Netdisco::Worker::Status';

use Try::Tiny;
use Moo::Role;
use Module::Load ();
use Scope::Guard 'guard';
use namespace::clean;

has 'job' => (
  is => 'rw',
);

has 'jobstat' => (
  is => 'rw',
  default => sub { Status->error("no worker for this action was successful") },
);

after 'run', 'run_workers' => sub {
  my $self = shift;
  $self->job->update_status($self->jobstat);
};

# mixin code to run workers loaded via plugins
sub run {
  my ($self, $job) = @_;

  die 'bad job to run()'
    unless ref $job eq 'App::Netdisco::Backend::Job';
  $self->job($job);

  my $action = $job->action;
  Module::Load::load 'App::Netdisco::Worker', $action;

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
  return $self->jobstat->defer('deferred job with no device creds')
    if ref $job->device and 0 == scalar @newuserconf;

  # back up and restore device_auth
  my $guard = guard { set(device_auth => \@userconf) };
  set(device_auth => \@newuserconf);

  my $store = Dancer::Factory::Hook->instance();
  my @phase_hooks = grep { m/^nd2_${action}_/ }
                         @{ (setting('_nd2worker_hooks') || []) };

  foreach my $phase ("nd2_${action}", @phase_hooks) {
    foreach my $stage (qw/init first second/) {
      my $hookname = "${phase}_${stage}";
      next unless scalar @{ $store->get_hooks_for($hookname) };
      $self->run_workers($hookname);
      return if $stage eq 'init' and $self->jobstat->not_ok;
    }
  }
}

sub run_workers {
  my $self = shift;
  my $hook = shift or return $self->jobstat->error('missing hook param');
  my $store = Dancer::Factory::Hook->instance();
  my $init = ($hook =~ m/_init$/);

  return unless scalar @{ $store->get_hooks_for($hook) };
  debug "running workers for hook: $hook";

  foreach my $worker (@{ $store->get_hooks_for($hook) }) {
    try {
      my $retval = $worker->($self->job);
      # could die or return undef or a scalar or Status or another class
      $self->jobstat($retval)
        if $init and ref $retval eq 'App::Netdisco::Worker::Status';
    }
    catch { $self->jobstat->error($_) if $init };

    last if $init and $self->jobstat->is_ok;
  }
}

true;
