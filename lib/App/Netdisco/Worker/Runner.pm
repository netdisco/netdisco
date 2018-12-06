package App::Netdisco::Worker::Runner;

use Dancer qw/:moose :syntax/;
use Dancer::Plugin::DBIC 'schema';
use App::Netdisco::Util::Device 'get_device';
use App::Netdisco::Util::Permission qw/check_acl_no check_acl_only/;
use aliased 'App::Netdisco::Worker::Status';

use Try::Tiny;
use Time::HiRes ();
use Module::Load ();
use Scope::Guard 'guard';
use Storable 'dclone';
use Sys::SigAction 'timeout_call';

use Moo::Role;
use namespace::clean;

with 'App::Netdisco::Worker::Loader';
has 'job' => ( is => 'rw' );

# mixin code to run workers loaded via plugins
sub run {
  my ($self, $job) = @_;

  die 'cannot reuse a worker' if $self->job;
  die 'bad job to run()'
    unless ref $job eq 'App::Netdisco::Backend::Job';

  $self->job($job);
  $job->device( get_device($job->device) );
  $self->load_workers();

  # finalise job status when we exit
  my $statusguard = guard { $job->finalise_status };

  my @newuserconf = ();
  my @userconf = @{ dclone (setting('device_auth') || []) };

  # reduce device_auth by only/no
  if (ref $job->device) {
    foreach my $stanza (@userconf) {
      my $no   = (exists $stanza->{no}   ? $stanza->{no}   : undef);
      my $only = (exists $stanza->{only} ? $stanza->{only} : undef);

      next if $no and check_acl_no($job->device, $no);
      next if $only and not check_acl_only($job->device, $only);

      push @newuserconf, dclone $stanza;
    }

    # per-device action but no device creds available
    return $job->add_status( Status->defer('deferred job with no device creds') )
      if 0 == scalar @newuserconf;
  }

  # back up and restore device_auth
  my $configguard = guard { set(device_auth => \@userconf) };
  set(device_auth => \@newuserconf);

  my $runner = sub {
    my ($self, $job) = @_;
    # roll everything back if we're testing
    my $txn_guard = $ENV{ND2_DB_ROLLBACK}
      ? schema('netdisco')->storage->txn_scope_guard : undef;

    # run check phase and if there are workers then one MUST be successful
    $self->run_workers('workers_check');

    # run other phases
    if ($job->check_passed) {
      $self->run_workers("workers_${_}") for qw/early main user/;
    }
  };

  my $maxtime = ((defined setting($job->action .'_timeout'))
    ? setting($job->action .'_timeout') : setting('workers')->{'timeout'});
  if ($maxtime) {
    debug sprintf '%s: running with timeout %ss', $job->action, $maxtime;
    if (timeout_call($maxtime, $runner, ($self, $job))) {
      debug sprintf '%s: timed out!', $job->action;
      $job->add_status( Status->error("job timed out after $maxtime sec") );
    }
  }
  else {
    $runner->($self, $job);
  }
}

sub run_workers {
  my $self = shift;
  my $job = $self->job or die error 'no job in worker job slot';

  my $set = shift
    or return $job->add_status( Status->error('missing set param') );
  return unless ref [] eq ref $self->$set and 0 < scalar @{ $self->$set };

  (my $phase = $set) =~ s/^workers_//;
  $job->enter_phase($phase);

  foreach my $worker (@{ $self->$set }) {
    try { $job->add_status( $worker->($job) ) }
    catch {
      debug "-> $_" if $_;
      $job->add_status( Status->error($_) );
    };
  }
}

true;
