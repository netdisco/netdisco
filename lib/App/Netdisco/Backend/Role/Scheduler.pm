package App::Netdisco::Backend::Role::Scheduler;

use Dancer qw/:moose :syntax :script/;

use NetAddr::IP;
use JSON::PP ();
use Algorithm::Cron;

use App::Netdisco::Util::MCE;
use App::Netdisco::JobQueue qw/jq_insert/;

use Role::Tiny;
use namespace::clean;

sub worker_begin {
  my $self = shift;
  my $wid = $self->wid;

  return debug "sch ($wid): no need for scheduler... skip begin"
    unless setting('schedule');

  debug "entering Scheduler ($wid) worker_begin()";

  foreach my $action (keys %{ setting('schedule') }) {
      my $config = setting('schedule')->{$action}
        or next;

      if (not $config->{when}) {
          error sprintf 'sch (%s): schedule %s is missing time spec',
            $wid, $action;
          next;
      }

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
      prctl sprintf 'nd2: #%s sched: inactive', $wid;
      return debug "sch ($wid): no need for scheduler... quitting"
  }

  my $coder = JSON::PP->new->utf8(0)->allow_nonref(1)->allow_unknown(1);

  while (1) {
      # sleep until some point in the next minute
      my $naptime = 60 - (time % 60) + int(rand(45));

      prctl sprintf 'nd2: #%s sched: idle', $wid;
      debug "sched ($wid): sleeping for $naptime seconds";

      sleep $naptime;
      prctl sprintf 'nd2: #%s sched: queueing', $wid;

      # NB next_time() returns the next *after* win_start
      my $win_start = time - (time % 60) - 1;
      my $win_end   = $win_start + 60;

      # if any job is due, add it to the queue
      foreach my $action (keys %{ setting('schedule') }) {
          my $sched = setting('schedule')->{$action} or next;
          my $real_action = ($sched->{action} || $action);

          # next occurence of job must be in this minute's window
          debug sprintf "sched ($wid): $real_action: win_start: %s, win_end: %s, next: %s",
            $win_start, $win_end, $sched->{when}->next_time($win_start);
          next unless $sched->{when}->next_time($win_start) <= $win_end;

          my @job_specs = ();

          if ($sched->{only} or $sched->{no}) {
              $sched->{label} = $action;
              push @job_specs, {
                action => 'scheduler',
                subaction => $coder->encode($sched),
              };
          }
          else {
              my @hostlist = ();

              foreach my $target (ref $sched->{device} eq ref [] ? @{ $sched->{device} }
                                                                 : $sched->{device}) {
                  # sanity checking
                  my $net = NetAddr::IP->new($target);
                  next if ($target
                    and (!$net or $net->num == 0 or $net->addr eq '0.0.0.0'));

                  if (scalar grep {$real_action eq $_} @{ setting('job_targets_prefix') }) {
                      push @hostlist, $target;
                  }
                  else {
                      @hostlist = map { (ref $_) ? $_->addr : undef }
                        (defined $target ? ($net->hostenum) : (undef));
                  }
              }

              foreach my $host (@hostlist) {
                push @job_specs, {
                  action => $real_action,
                  device => $host,
                  port   => $sched->{port},
                  subaction => $sched->{extra},
                };
              }
          }

          info sprintf 'sched (%s): queueing %s %s jobs',
            $wid, (scalar @job_specs), $real_action;
          jq_insert( \@job_specs );
      }
  }
}

1;
