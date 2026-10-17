#!/usr/bin/env perl

# workers.queues reserves workers for some actions. An action in a queue is run
# by that queue only: the general pool leaves it alone, so the general pool
# reports every reserved action as one to leave out. A queue that cannot run
# anything (no workers, no actions) is ignored and must not take its actions
# away from the general pool.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use Dancer qw/:moose :script !pass/;

config->{logger} = 'null';

use App::Netdisco::Backend::Queues qw/worker_queues queue_for total_workers/;

sub configure {
  my ($tasks, $queues) = @_;
  config->{workers}->{tasks}  = $tasks;
  config->{workers}->{queues} = $queues;
}

subtest 'workerQueues__no_queues__is_the_general_pool_leaving_nothing_out' => sub {
  configure(4, {});
  is_deeply [ worker_queues() ],
    [{ name => 'general', tasks => 4, actions => [], only => 0 }],
    'one queue, which takes every action';
  is total_workers(), 4, 'all workers are in it';

  configure(4, undef);
  is scalar(my @q = worker_queues()), 1, 'an unset queues is no queues';
};

subtest 'workerQueues__reserved_queues__are_cut_out_of_the_general_pool' => sub {
  configure(3, {
    vlans => { tasks => 2, actions => ['VLAN', 'portcontrol::port'] },
    loc   => { tasks => 1, actions => 'location' },
  });

  is_deeply [ worker_queues() ], [
    { name => 'general', tasks => 3, only => 0,
      actions => [qw/location portcontrol vlan/] },
    { name => 'loc',     tasks => 1, only => 1, actions => ['location'] },
    { name => 'vlans',   tasks => 2, only => 1,
      actions => [qw/vlan portcontrol/] },
  ], 'general leaves out the lowercased base action of every reserved queue';
  is total_workers(), 6, 'workers are counted over all queues';
};

subtest 'queueFor__an_action__is_run_by_the_queue_that_owns_it' => sub {
  configure(1, { vlans => { tasks => 1, actions => ['vlan', 'portcontrol'] } });
  my @queues = worker_queues();

  is queue_for(\@queues, $_->[0])->{name}, $_->[1], $_->[0]
    for ([vlan => 'vlans'], [portcontrol => 'vlans'], ['PortControl::x' => 'vlans'],
         [discover => 'general'], [primeskiplist => 'general']);
};

subtest 'queueFor__general_pool_without_workers__hands_its_jobs_to_a_reserved_queue' => sub {
  configure(0, { vlans => { tasks => 1, actions => ['vlan'] } });
  my @queues = worker_queues();

  is queue_for(\@queues, 'primeskiplist')->{name}, 'vlans',
    'internal jobs still have workers to run on';
  is queue_for(\@queues, 'vlan')->{name}, 'vlans', 'a reserved action is unchanged';
};

subtest 'workerQueues__queue_that_cannot_run_anything__is_ignored' => sub {
  configure(2, {
    idle    => { tasks => 0, actions => ['discover'] },
    nothing => { tasks => 3, actions => [] },
    absent  => { tasks => 3 },
    off     => undef,
  });

  is_deeply [ worker_queues() ],
    [{ name => 'general', tasks => 2, actions => [], only => 0 }],
    'its actions stay with the general pool';
};

subtest 'workerQueues__tasks_in_a_queue__are_scaled_like_workers_tasks' => sub {
  configure(0, { vlans => { tasks => 'AUTO / 1', actions => ['vlan'] } });
  cmp_ok total_workers(), '>', 0, 'AUTO arithmetic is understood';

  configure(0, { vlans => { tasks => 2, actions => ['vlan'] } });
  is total_workers(), 2, 'a node with no general pool still runs the queue';
};

subtest 'workerQueues__tasks_that_make_no_sense__are_no_workers' => sub {
  foreach my $tasks ('AUTO - 100000', 'AUTO * 0', 'AUTO * foo', 'many', -1, undef) {
    configure($tasks, { vlans => { tasks => $tasks, actions => ['vlan'] } });
    is total_workers(), 0, defined $tasks ? $tasks : 'undef';
  }
};

subtest 'workerQueues__action_in_two_queues__dies' => sub {
  configure(1, {
    a => { tasks => 1, actions => ['vlan'] },
    b => { tasks => 1, actions => ['VLAN::x'] },
  });
  eval { worker_queues() };
  like $@, qr/action 'vlan' is in both queue 'a' and queue 'b'/,
    'the backend will not guess which queue is meant';
};

done_testing;
