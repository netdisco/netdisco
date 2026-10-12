#!/usr/bin/env perl

# The manager tops up each worker queue from the job queue on its own: a
# reserved queue is offered only jobs for its actions and the general pool
# those that are left. A job goes to the local queue of the workers that were
# offered it, and the jobs a backend finds booked to it on startup, and its
# internal jobs, go to the queue which runs their action.

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

my (@queued, @booked, @asked);

# Manager.pm imports these when it compiles and namespace::clean then hides
# them, so they must be replaced before it is loaded. the fake job queue
# filters as the real one does.
BEGIN {
  no warnings 'redefine';
  *App::Netdisco::JobQueue::jq_getsome = sub {
    my ($slots, %queue) = @_;
    push @asked, [ $slots, $queue{only}, [ @{ $queue{actions} || [] } ] ];
    return () unless $slots > 0;

    my %listed = map { $_ => 1 } @{ $queue{actions} || [] };
    my @found = grep { ($listed{$_->action} ? 1 : 0) == ($queue{only} ? 1 : 0) } @queued;
    @queued = grep { my $q = $_; not grep { $_ == $q } @found } @queued;
    return splice @found, 0, $slots;
  };
  *App::Netdisco::JobQueue::jq_lock = sub { 1 };
  *App::Netdisco::JobQueue::jq_locked = sub { @booked };
  *App::Netdisco::JobQueue::jq_warm_thrusters = sub { };
  *App::Netdisco::Util::MCE::prctl = sub { die "idle\n" if $_[0] =~ m/mgr: idle$/ };
}

require App::Netdisco::Backend::Role::Manager;

{
  no warnings 'redefine';
  *Proc::ProcessTable::new = sub { bless {}, shift };
  *Proc::ProcessTable::table = sub { [] };
}

{
  package FakeQueue;
  sub new { bless { pending => ($_[1] || 0), jobs => [] }, $_[0] }
  sub pending { $_[0]->{pending} }
  sub enqueuep { my $self = shift; shift; push @{ $self->{jobs} }, @_ }
  sub actions { [ map { $_->action } @{ $_[0]->{jobs} } ] }

  package FakeManager;
  sub wid { 1 }
}

sub job {
  my ($action, $device) = @_;
  return App::Netdisco::Backend::Job->new({
    job => 1, action => $action, device => $device });
}

# a general pool of 2 workers and a reserved queue of 2 for vlan
sub manager {
  my %pending = @_;
  return bless { queues => [
    { name => 'general', tasks => 2, only => 0, actions => ['vlan'],
      queue => FakeQueue->new($pending{general}) },
    { name => 'vlans', tasks => 2, only => 1, actions => ['vlan'],
      queue => FakeQueue->new($pending{vlans}) },
  ] }, 'FakeManager';
}

sub run_body {
  my $self = shift;
  my $stopped = '';
  try { App::Netdisco::Backend::Role::Manager::worker_body($self) }
  catch { $stopped = $_ };
  return $stopped;
}

subtest 'workerBody__jobs_for_reserved_and_other_actions__go_to_their_own_workers' => sub {
  @asked = ();
  @queued = (job('discover', '10.1.1.1'), job('vlan', '10.1.1.2'),
             job('macsuck', '10.1.1.3'));
  my $self = manager();

  is run_body($self), "idle\n", 'the manager loop completes';
  my ($general, $vlans) = map { $_->{queue} } @{ $self->{queues} };
  is_deeply $vlans->actions, ['vlan'], 'the reserved queue has the vlan job';
  is_deeply [ sort @{ $general->actions } ], [qw/discover macsuck/],
    'the general pool has the rest';
};

subtest 'workerBody__each_queue__is_offered_the_slots_it_has_free' => sub {
  @asked = ();
  @queued = ();

  run_body(manager(general => 1, vlans => 2));
  is_deeply \@asked, [
    [ 1, 0, ['vlan'] ],
    [ 0, 1, ['vlan'] ],
  ], 'a queue with a backlog is asked for fewer jobs, one that is full for none';
};

subtest 'workerBody__a_full_reserved_queue__does_not_pass_its_jobs_to_the_general_pool' => sub {
  @asked = ();
  @queued = (job('vlan', '10.1.1.2'));
  my $self = manager(vlans => 2);

  run_body($self);
  my ($general, $vlans) = map { $_->{queue} } @{ $self->{queues} };
  is_deeply $general->actions, [], 'the general pool does not take the vlan job';
  is_deeply $vlans->actions, [], 'the reserved queue is full';
  is scalar @queued, 1, 'the job waits in the job queue';
};

subtest 'workerBegin__booked_and_internal_jobs__go_to_the_queue_for_their_action' => sub {
  @booked = (job('vlan', '10.1.1.2'), job('discover', '10.1.1.1'));
  my $self = manager();

  App::Netdisco::Backend::Role::Manager::worker_begin($self);
  my ($general, $vlans) = map { $_->{queue} } @{ $self->{queues} };
  is_deeply $vlans->actions, ['vlan'], 'a booked vlan job is requeued for the vlan workers';
  is_deeply [ sort @{ $general->actions } ], [qw/discover primeskiplist/],
    'other booked jobs and primeskiplist go to the general pool';
};

done_testing;
