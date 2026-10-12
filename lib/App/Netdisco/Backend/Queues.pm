package App::Netdisco::Backend::Queues;

use strict;
use warnings;

use Dancer qw/:moose :syntax :script/;
use App::Netdisco::Util::MCE 'parse_max_workers';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  worker_queues
  queue_for
  total_workers
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Backend::Queues

=head1 DESCRIPTION

The backend normally runs all jobs on one pool of workers (C<workers.tasks>).
The C<workers.queues> setting reserves workers for particular actions, so that
a long queue of one kind of job (say, discovery) cannot keep another (say,
C<portcontrol>) waiting for a free worker:

 workers:
   tasks: 'AUTO * 2'
   queues:
     portcontrol:
       tasks: 2
       actions: [portcontrol, vlan]

An action named in a queue is run only by the workers of that queue, and the
general pool never takes it. A queue without workers or actions is ignored,
and its actions stay with the general pool.

=head1 EXPORT_OK

=head2 worker_queues

Returns a list of hash references, each with C<name>, C<tasks> (the number of
workers), C<actions> and C<only>. The first is always the general pool, which
lists the reserved actions it must leave alone (C<only> false). The others are
the reserved queues in name order, which list the actions they take (C<only>
true). Dies if an action is in more than one queue.

=head2 queue_for( \@queues, $action )

Returns the entry of C<@queues> (as from C<worker_queues>) which runs the
given action. Actions not reserved go to the general pool, or if that has no
workers, to the first reserved queue.

=head2 total_workers

The number of workers over all queues.

=cut

sub worker_queues {
  my $conf = setting('workers')->{queues};
  $conf = {} unless ref {} eq ref $conf;

  my (@reserved, %owner);

  foreach my $name (sort keys %$conf) {
    my $queue = $conf->{$name};
    next unless ref {} eq ref $queue;

    my $tasks   = _tasks($queue->{tasks});
    my @actions = _base_actions($queue->{actions});
    next unless $tasks and scalar @actions;

    foreach my $action (@actions) {
      die sprintf "workers: action '%s' is in both queue '%s' and queue '%s'\n",
        $action, $owner{$action}, $name if exists $owner{$action};
      $owner{$action} = $name;
    }

    push @reserved, { name => $name, tasks => $tasks,
                      actions => \@actions, only => 1 };
  }

  return ({
    name    => 'general',
    tasks   => _tasks(setting('workers')->{tasks}),
    actions => [ sort keys %owner ],
    only    => 0,
  }, @reserved);
}

sub queue_for {
  my ($queues, $action) = @_;
  $action = _base_action($action);

  foreach my $queue (@$queues) {
    return $queue if $queue->{only}
      and scalar grep { $_ eq $action } @{ $queue->{actions} };
  }

  # a node with only reserved queues still has to run its internal jobs
  return $queues->[0] if $queues->[0]->{tasks};
  return $queues->[1] || $queues->[0];
}

sub total_workers {
  my $total = 0;
  $total += $_->{tasks} for worker_queues();
  return $total;
}

# parse_max_workers can hand back a negative number, or the setting unparsed
sub _tasks {
  my $tasks = parse_max_workers(shift);
  return ($tasks =~ m/^\d+$/ ? $tasks : 0);
}

# a job for 'action::stage' is run by the queue of 'action'
sub _base_action {
  my $action = lc(shift || '');
  $action =~ s/::.*//;
  return $action;
}

sub _base_actions {
  my $actions = shift;
  $actions = [ $actions ] if defined $actions and ref [] ne ref $actions;

  my %seen;
  return grep { length($_) and not $seen{$_}++ }
         map  { _base_action($_) } @{ $actions || [] };
}

1;
