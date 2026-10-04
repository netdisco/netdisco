#!/usr/bin/env perl

# The job action is matched as text; the device is matched as a pattern.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use App::Netdisco::Backend::Job;
use App::Netdisco::JobQueue ();
use App::Netdisco::Util::MCE ();
use Proc::ProcessTable;

use Try::Tiny;

use Dancer qw/:moose :script !pass/;

config->{logger} = 'null';
config->{workers}->{tasks} = 1;

my (@queued, @locked, @running);

# Manager.pm imports these when it compiles and namespace::clean then hides
# them, so they must be replaced before it is loaded.
BEGIN {
  no warnings 'redefine';
  *App::Netdisco::JobQueue::jq_getsome = sub { my @jobs = @queued; @queued = (); @jobs };
  *App::Netdisco::JobQueue::jq_lock = sub { push @locked, shift; 1 };
  *App::Netdisco::Util::MCE::prctl = sub { die "idle\n" if $_[0] =~ m/mgr: idle$/ };
}

require App::Netdisco::Backend::Role::Manager;

{
  no warnings 'redefine';
  *Proc::ProcessTable::new = sub { bless {}, shift };
  *Proc::ProcessTable::table = sub {
    [ map { bless { cmndline => $_ }, 'FakeProcess' } @running ];
  };
}

{
  package FakeProcess;
  sub cmndline { $_[0]->{cmndline} }

  package FakeQueue;
  sub pending { 0 }
  sub enqueuep { }

  package FakeManager;
  sub wid { 1 }
}

sub job {
  my ($action, $device) = @_;
  return App::Netdisco::Backend::Job->new({
    job => 1, action => $action, device => $device });
}

# runs one pass of the manager loop, returning how it stopped and
# whether the queued job was booked out
sub manage {
  my ($queued_job, $running_job) = @_;
  @running = (sprintf 'nd2: #2 poll: #7: %s', job(@$running_job)->display_name);
  @queued = (job(@$queued_job));
  @locked = ();

  my $self = bless { queue => bless({}, 'FakeQueue') }, 'FakeManager';
  my $stopped = '';
  try { App::Netdisco::Backend::Role::Manager::worker_body($self) }
  catch { $stopped = $_ };
  return ($stopped, scalar @locked);
}

subtest 'workerBody__an_action_that_is_not_a_valid_pattern__still_dispatches_it' => sub {
  my ($stopped, $dispatched) = manage(['cf_(', '10.1.1.1'], ['discover', '10.1.1.1']);
  is $stopped, "idle\n", 'the manager loop completes';
  is $dispatched, 1, 'the job is booked out';
};

subtest 'workerBody__an_action_resembling_a_running_one__still_dispatches_it' => sub {
  my ($stopped, $dispatched) = manage(['disc.ver', '10.1.1.1'], ['discover', '10.1.1.1']);
  is $stopped, "idle\n", 'the manager loop completes';
  is $dispatched, 1, 'disc.ver is not mistaken for discover';
};

subtest 'workerBody__the_same_job_already_running__skips_it' => sub {
  my ($stopped, $dispatched) = manage(['discover', '10.1.1.1'], ['discover', '10.1.1.1']);
  is $stopped, "idle\n", 'the manager loop completes';
  is $dispatched, 0, 'the duplicate is not booked out';
};

subtest 'workerBody__a_device_matching_a_running_one_as_a_pattern__still_skips_it' => sub {
  my ($stopped, $dispatched) = manage(['discover', '10.1.1.1'], ['discover', '10.111.1.5']);
  is $stopped, "idle\n", 'the manager loop completes';
  is $dispatched, 0, 'the device match is unchanged';
};

done_testing;
