package App::Netdisco::Daemon::Worker::Manager;

use Dancer qw/:moose :syntax :script/;

use List::Util 'sum';
use App::Netdisco::Util::Daemon;

use Role::Tiny;
use namespace::clean;

use App::Netdisco::JobQueue qw/jq_locked jq_getsome jq_getsomep jq_lock/;
use MCE::Util ();

sub worker_begin {
  my $self = shift;
  my $wid = $self->wid;

  return debug "mgr ($wid): no need for manager... skip begin"
    if setting('workers')->{'no_manager'};

  debug "entering Manager ($wid) worker_begin()";

  # requeue jobs locally
  debug "mgr ($wid): searching for jobs booked to this processing node";
  my @jobs = jq_locked;

  if (scalar @jobs) {
      info sprintf "mgr (%s): found %s jobs booked to this processing node",
        $wid, scalar @jobs;
      $self->{queue}->enqueuep(100, @jobs);
  }
}

sub worker_body {
  my $self = shift;
  my $wid = $self->wid;

  if (setting('workers')->{'no_manager'}) {
      prctl sprintf 'netdisco-daemon: worker #%s manager: inactive', $wid;
      return debug "mgr ($wid): no need for manager... quitting"
  }

  while (1) {
      prctl sprintf 'netdisco-daemon: worker #%s manager: gathering', $wid;
      my $num_slots = 0;

      $num_slots =
        MCE::Util::_parse_max_workers( setting('workers')->{tasks} )
          - $self->{queue}->pending();
      debug "mgr ($wid): getting potential jobs for $num_slots workers (HP)";

      # get some high priority jobs
      # TODO also check for stale jobs in Netdisco DB
      foreach my $job ( jq_getsomep($num_slots) ) {

          # mark job as running
          next unless jq_lock($job);
          info sprintf "mgr (%s): job %s booked out for this processing node",
            $wid, $job->job;

          # copy job to local queue
          $self->{queue}->enqueuep(100, $job);
      }

      $num_slots =
        MCE::Util::_parse_max_workers( setting('workers')->{tasks} )
          - $self->{queue}->pending();
      debug "mgr ($wid): getting potential jobs for $num_slots workers (NP)";

      # get some normal priority jobs
      # TODO also check for stale jobs in Netdisco DB
      foreach my $job ( jq_getsome($num_slots) ) {

          # mark job as running
          next unless jq_lock($job);
          info sprintf "mgr (%s): job %s booked out for this processing node",
            $wid, $job->job;

          # copy job to local queue
          $self->{queue}->enqueue($job);
      }

      debug "mgr ($wid): sleeping now...";
      prctl sprintf 'netdisco-daemon: worker #%s manager: idle', $wid;
      sleep( setting('workers')->{sleep_time} || 1 );
  }
}

1;
