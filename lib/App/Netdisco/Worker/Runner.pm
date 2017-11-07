package App::Netdisco::Worker::Runner;

use Dancer qw/:moose :syntax/;
use Dancer::Factory::Hook;

use App::Netdisco::Util::Permission qw/check_acl_no check_acl_only/;
use App::Netdisco::Util::Device 'get_device';
use aliased 'App::Netdisco::Worker::Status';

use Try::Tiny;
use Module::Load ();
use Scope::Guard 'guard';

use Moo::Role;
use namespace::clean;

has 'job' => ( is => 'rw' );

# mixin code to run workers loaded via plugins
sub run {
  my ($self, $job) = @_;

  die 'cannot reuse a worker' if $self->job;
  die 'bad job to run()'
    unless ref $job eq 'App::Netdisco::Backend::Job';

  $self->job($job);
  $job->device( get_device($job->device) );
  Module::Load::load 'App::Netdisco::Worker' => $job->action;

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

    # per-device action but no device creds available
    return $job->add_status( Status->defer('deferred job with no device creds') )
      if 0 == scalar @newuserconf;
  }

  # back up and restore device_auth
  my $configguard = guard { set(device_auth => \@userconf) };
  set(device_auth => \@newuserconf);

  # finalise job status when we exit
  my $statusguard = guard { $job->finalise_status };

  # run check phase and if there are workers then one MUST be successful
  $self->run_workers('nd2_core_check');
  return if not $job->check_passed;

  # run other phases
  $self->run_workers("nd2_core_${_}") for qw/early main user/;
}

sub run_workers {
  my $self = shift;
  my $job  = $self->job or die error 'no job in worker job slot';
  my $hook = shift
    or return $job->add_status( Status->error('missing hook param') );

  my $store = Dancer::Factory::Hook->instance();
  (my $phase = $hook) =~ s/^nd2_core_//;

  return unless scalar @{ $store->get_hooks_for($hook) };
  $job->enter_phase($phase);

  foreach my $worker (@{ $store->get_hooks_for($hook) }) {
    try { $job->add_status( $worker->($job) ) }
    catch {
      debug "=> $_" if $_;
      $job->add_status( Status->error($_) );
    };
  }
}

true;
