package App::Netdisco::Daemon::Worker::Manager;

use Dancer qw/:moose :syntax :script/;

use Role::Tiny;
use namespace::clean;

use List::Util 'sum';
use App::Netdisco::JobQueue qw/jq_locked jq_getsome jq_lock/;

sub worker_begin {
  my $self = shift;
  my $wid = $self->wid;
  debug "entering Manager ($wid) worker_begin()";

  if (setting('workers')->{'no_manager'}) {
      return debug "mgr ($wid): no need for manager... skip begin";
  }

  # requeue jobs locally
  debug "mgr ($wid): searching for jobs booked to this processing node";
  my @jobs = jq_locked;

  if (scalar @jobs) {
      info sprintf "mgr (%s): found %s jobs booked to this processing node", $wid, scalar @jobs;
      $self->do('add_jobs', @jobs);
  }
}

sub worker_body {
  my $self = shift;
  my $wid = $self->wid;

  return debug "mgr ($wid): no need for manager... quitting"
    if setting('workers')->{'no_manager'};

  my $num_slots = sum( 0, map { setting('workers')->{$_} }
                              values %{setting('job_type_keys')} );

  while (1) {
      debug "mgr ($wid): getting potential jobs for $num_slots workers";

      # get some pending jobs
      # TODO also check for stale jobs in Netdisco DB
      foreach my $job ( jq_getsome($num_slots) ) {

          # check for available local capacity
          my $job_type = setting('job_types')->{$job->action};
          next unless $job_type and $self->do('capacity_for', $job_type);
          debug sprintf "mgr (%s): processing node has capacity for job %s (%s)",
            $wid, $job->id, $job->action;

          # mark job as running
          next unless jq_lock($job);
          info sprintf "mgr (%s): job %s booked out for this processing node",
            $wid, $job->id;

          # copy job to local queue
          $self->do('add_jobs', $job);
      }

      debug "mgr ($wid): sleeping now...";
      sleep( setting('workers')->{sleep_time} || 2 );
  }
}

1;
