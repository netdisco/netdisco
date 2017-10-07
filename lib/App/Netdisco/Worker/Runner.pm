package App::Netdisco::Worker::Runner;

use Dancer qw/:moose :syntax/;
use Dancer::Factory::Hook;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Permission qw/check_acl_no check_acl_only/;

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
  default => sub { Status->error('check phase did not pass for this action') },
);

after 'run', 'run_workers' => sub {
  my $self = shift;
  $self->job->update_status($self->jobstat);
};

# mixin code to run workers loaded via plugins
sub run {
  my ($self, $job) = @_;

  die 'cannot reuse a worker' if $self->job;
  die 'bad job to run()'
    unless ref $job eq 'App::Netdisco::Backend::Job';
  $self->job($job);

  my $action = $job->action;
  Module::Load::load 'App::Netdisco::Worker' => $action;

  my @newuserconf = ();
  my @userconf = @{ setting('device_auth') || [] };

  # reduce device_auth by only/no
  if (ref $job->device) {
    foreach my $stanza (@userconf) {
      my $no   = (exists $stanza->{no}   ? $stanza->{no}   : undef);
      my $only = (exists $stanza->{only} ? $stanza->{only} : undef);

      next if $no and check_acl_no($job->device, $no);
      next if $only and not check_acl_only($job->device, $only);

      push @newuserconf, $stanza;
    }
  }

  # per-device action but no device creds available
  return $self->jobstat->defer('deferred job with no device creds')
    if ref $job->device and 0 == scalar @newuserconf;

  # back up and restore device_auth
  my $guard = guard { set(device_auth => \@userconf) };
  set(device_auth => \@newuserconf);

  # run check phase
  # optional - but if there are workers then one MUST return done
  my $store = Dancer::Factory::Hook->instance();
  $self->run_workers('nd2_core_check');
  return if scalar @{ $store->get_hooks_for('nd2_core_check') }
            and $self->jobstat->not_ok;

  # run other phases
  $self->jobstat( Status->error('no worker succeeded during main phase') );
  $self->run_workers("nd2_core_${_}") for qw/early main user/;
}

sub run_workers {
  my $self = shift;
  my $hook = shift or return $self->jobstat->error('missing hook param');
  my $store = Dancer::Factory::Hook->instance();
  (my $phase = $hook) =~ s/^nd2_core_//;

  return unless scalar @{ $store->get_hooks_for($hook) };
  debug "running workers for hook: $hook";
  my $max_level = 0;

  foreach my $worker (@{ $store->get_hooks_for($hook) }) {
    try {
      # could die or return undef or a scalar or Status or another class
      my $retval = $worker->($self->job);

      if (ref $retval eq 'App::Netdisco::Worker::Status') {
        # update (save) the status if we're in check or main phases
        # because these logs can end up in the job queue as status message
        $self->jobstat($retval)
          if ($phase =~ m/^(?:check|main)$/) and $retval->level >= $max_level;

        debug $retval->log if $retval->log;
      }
    }
    # errors at most phases are ignored
    catch {
      $self->jobstat->error($_) if $phase eq 'check';
      debug $_ if $_;
    };

    # any successful check is a GO!
    last if $phase eq 'check' and $self->jobstat->is_ok;
  }
}

true;
