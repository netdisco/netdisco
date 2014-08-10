package App::Netdisco::Daemon::Worker::Scheduler;

use Dancer qw/:moose :syntax :script/;

use Algorithm::Cron;
use App::Netdisco::Util::Daemon;

use Role::Tiny;
use namespace::clean;

use App::Netdisco::JobQueue qw/jq_insert/;

sub worker_begin {
  my $self = shift;
  my $wid = $self->wid;

  return debug "sch ($wid): no need for scheduler... skip begin"
    unless setting('schedule');

  debug "entering Scheduler ($wid) worker_begin()";

  foreach my $action (keys %{ setting('schedule') }) {
      my $config = setting('schedule')->{$action};

      # accept either single crontab format, or individual time fields
      $config->{when} = Algorithm::Cron->new(
        base => 'local',
        %{
          (ref {} eq ref $config->{when})
            ? $config->{when}
            : {crontab => $config->{when}}
        }
      );
  }
}

sub worker_body {
  my $self = shift;
  my $wid = $self->wid;

  unless (setting('schedule')) {
      prctl sprintf 'netdisco-daemon: worker #%s scheduler: inactive', $wid;
      return debug "sch ($wid): no need for scheduler... quitting"
  }

  while (1) {
      # sleep until some point in the next minute
      my $naptime = 60 - (time % 60) + int(rand(45));

      prctl sprintf 'netdisco-daemon: worker #%s scheduler: idle', $wid;
      debug "sched ($wid): sleeping for $naptime seconds";

      sleep $naptime;
      prctl sprintf 'netdisco-daemon: worker #%s scheduler: queueing', $wid;

      # NB next_time() returns the next *after* win_start
      my $win_start = time - (time % 60) - 1;
      my $win_end   = $win_start + 60;

      # if any job is due, add it to the queue
      foreach my $action (keys %{ setting('schedule') }) {
          my $sched = setting('schedule')->{$action};

          # next occurence of job must be in this minute's window
          debug sprintf "sched ($wid): $action: win_start: %s, win_end: %s, next: %s",
            $win_start, $win_end, $sched->{when}->next_time($win_start);
          next unless $sched->{when}->next_time($win_start) <= $win_end;

          # queue it!
          info "sched ($wid): queueing $action job";
          jq_insert({
            action => $action,
            device => $sched->{device},
            extra  => $sched->{extra},
          });
      }
  }
}

1;
