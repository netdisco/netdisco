package App::Netdisco::Daemon::Worker::Scheduler;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use Algorithm::Cron;
use Try::Tiny;

use Role::Tiny;
use namespace::clean;

my $jobactions = {
  map {$_ => undef} qw/
      discoverall
      arpwalk
      macwalk
  /
#    saveconfigs
#    nbtwalk
#    backup
};

sub worker_begin {
  my $self = shift;
  my $wid = $self->wid;
  debug "entering Scheduler ($wid) worker_begin()";

  foreach my $a (keys %$jobactions) {
      next unless setting('housekeeping')
        and exists setting('housekeeping')->{$a};
      my $config = setting('housekeeping')->{$a};

      # accept either single crontab format, or individual time fields
      my $cron = Algorithm::Cron->new(
        base => 'local',
        %{
          (ref {} eq ref $config->{when})
            ? $config->{when}
            : {crontab => $config->{when}}
        }
      );

      $jobactions->{$a} = $config;
      $jobactions->{$a}->{when} = $cron;
  }
}

sub worker_body {
  my $self = shift;
  my $wid = $self->wid;

  while (1) {
      # sleep until some point in the next minute
      my $naptime = 60 - (time % 60) + int(rand(45));
      debug "sched ($wid): sleeping for $naptime seconds";
      sleep $naptime;

      # NB next_time() returns the next *after* win_start
      my $win_start = time - (time % 60) - 1;
      my $win_end   = $win_start + 60;

      # if any job is due, add it to the queue
      foreach my $a (keys %$jobactions) {
          next unless defined $jobactions->{$a};
          my $sched = $jobactions->{$a};

          # next occurence of job must be in this minute's window
          debug sprintf "sched ($wid): $a: win_start: %s, win_end: %s, next: %s",
            $win_start, $win_end, $sched->{when}->next_time($win_start);
          next unless $sched->{when}->next_time($win_start) <= $win_end;

          # queue it!
          # due to a table constraint, this will (intentionally) fail if a
          # similar job is already queued.
          try {
              debug "sched ($wid): queueing $a job";
              schema('netdisco')->resultset('Admin')->create({
                action => $a,
                device => ($sched->{device} || undef),
                subaction => ($sched->{extra} || undef),
                status => 'queued',
              });
          }
          catch {
              debug "sched ($wid): action $a was not queued (dupe?)";
          };
      }
  }
}

1;
