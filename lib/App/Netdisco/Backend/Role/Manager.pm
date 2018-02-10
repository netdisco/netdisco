package App::Netdisco::Backend::Role::Manager;

use Dancer qw/:moose :syntax :script/;

use List::Util 'sum';
use App::Netdisco::Util::MCE;

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
  debug "mgr ($wid): building acl hints (please be patient...)";
  jq_warm_thrusters;

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

      $num_slots = parse_max_workers( setting('workers')->{tasks} )
                     - $self->{queue}->pending();
      debug "mgr ($wid): getting potential jobs for $num_slots workers";

      foreach my $job ( jq_getsome($num_slots) ) {
          next if $seen_job{ $memoize->($job) }++;

          # mark job as running
          next unless jq_lock($job);
          info sprintf "mgr (%s): job %s booked out for this processing node",
            $wid, $job->id;

          # copy job to local queue
          $self->{queue}->enqueuep($job->job_priority, $job);
      }

      #if (scalar grep {$_ > 1} values %seen_job) {
      #  debug 'WARNING: saw duplicate jobs after getsome()';
      #  use DDP; debug p %seen_job;
      #}

      debug "mgr ($wid): sleeping now...";
      prctl sprintf 'nd2: #%s mgr: idle', $wid;
      sleep( setting('workers')->{sleep_time} || 1 );
  }
}

1;
