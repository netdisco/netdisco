package App::Netdisco::Backend::Role::Manager;

use Dancer qw/:moose :syntax :script/;

use List::Util 'sum';
use Proc::ProcessTable;
use App::Netdisco::Util::MCE;

use App::Netdisco::Backend::Job;
use App::Netdisco::JobQueue
  qw/jq_locked jq_getsome jq_lock jq_warm_thrusters/;

use Role::Tiny;
use namespace::clean;

sub worker_begin {
  my $self = shift;
  my $wid = $self->wid;

  return debug "mgr ($wid): no need for manager... skip begin"
    if setting('workers')->{'no_manager'};

  debug "entering Manager ($wid) worker_begin()";

  # job queue initialisation
  # the expensive parts of this were moved to primeskiplist job
  jq_warm_thrusters;

  # queue a job to rebuild the device action skip list
  $self->{queue}->enqueuep(200,
    App::Netdisco::Backend::Job->new({ job => 0, action => 'primeskiplist' }));

  # requeue jobs locally
  debug "mgr ($wid): searching for jobs booked to this processing node";
  my @jobs = jq_locked;

  if (scalar @jobs) {
      info sprintf "mgr (%s): found %s jobs booked to this processing node",
        $wid, scalar @jobs;
      $self->{queue}->enqueuep(100, @jobs);
  }
}

# creates a 'signature' for each job so that we can check for duplicates ...
# it happens from time to time due to the distributed nature of the job queue
# and manager(s) - also kinder to the DB to skip here rather than jq_lock()
my $memoize = sub {
  no warnings 'uninitialized';
  my $job = shift;
  return join chr(28), map {$job->{$_}}
    (qw/action port subaction/, ($job->{device_key} ? 'device_key' : 'device'));
};

sub worker_body {
  my $self = shift;
  my $wid = $self->wid;

  if (setting('workers')->{'no_manager'}) {
      prctl sprintf 'nd2: #%s mgr: inactive', $wid;
      return debug "mgr ($wid): no need for manager... quitting"
  }

  while (1) {
      prctl sprintf 'nd2: #%s mgr: gathering', $wid;
      my $num_slots = 0;
      my %seen_job = ();

      # this does have a race condition, but the jobs we're protecting
      # against are likely to be long running
      my $t = Proc::ProcessTable->new( 'enable_ttys' => 0 );

      $num_slots = parse_max_workers( setting('workers')->{tasks} )
                      - $self->{queue}->pending();
      debug "mgr ($wid): getting potential jobs for $num_slots workers"
        if not $ENV{ND2_SINGLE_WORKER};

      JOB: foreach my $job ( jq_getsome($num_slots) ) {
          my $display_name = $job->action .' '. ($job->device || '');

          if ($seen_job{ $memoize->($job) }++) {
              debug "mgr ($wid): duplicate queue job detected: $display_name";
              next JOB;
          }

          # 1392 check for any of the same job running already
          if ($job->device) {
              foreach my $p ( @{$t->table} ) {
                  if ($p->cmndline
                        and $p->cmndline =~ m/nd2: #\d+ poll: #\d+: ${display_name}/) {
                      debug "mgr ($wid): duplicate running job detected: $display_name";
                      next JOB;
                  }
              }
          }

          # mark job as running
          jq_lock($job) or next JOB;
          info sprintf "mgr (%s): job %s booked out for this processing node",
            $wid, $job->id;

          # copy job to local queue
          $self->{queue}->enqueuep($job->job_priority, $job);
      }

      #if (scalar grep {$_ > 1} values %seen_job) {
      #  debug 'WARNING: saw duplicate jobs after getsome()';
      #  use DDP; debug p %seen_job;
      #}

      debug "mgr ($wid): sleeping now..." if not $ENV{ND2_SINGLE_WORKER};
      prctl sprintf 'nd2: #%s mgr: idle', $wid;
      sleep( setting('workers')->{sleep_time} || 1 );
  }
}

1;
