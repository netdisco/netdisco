package App::Netdisco::Daemon::Worker::Common;

use Dancer qw/:moose :syntax :script/;

use Try::Tiny;
use App::Netdisco::Util::Daemon;

use Role::Tiny;
use namespace::clean;

use App::Netdisco::JobQueue qw/jq_defer jq_complete/;

sub worker_body {
  my $self = shift;
  my $wid = $self->wid;

  while (1) {
      prctl sprintf 'netdisco-daemon: worker #%s poller: idle', $wid;

      my $job = $self->{queue}->dequeue(1);
      next unless defined $job;
      my $action = $job->action;

      try {
          $job->started(scalar localtime);
          prctl sprintf 'netdisco-daemon: worker #%s poller: working on #%s: %s',
            $wid, $job->job, $job->summary;
          info sprintf "pol (%s): starting %s job(%s) at %s",
            $wid, $action, $job->job, $job->started;
          my ($status, $log) = $self->$action($job);
          $job->status($status);
          $job->log($log);
      }
      catch {
          $job->status('error');
          $job->log("error running job: $_");
          $self->sendto('stderr', $job->log ."\n");
      };

      $self->close_job($job);
  }
}

sub close_job {
  my ($self, $job) = @_;
  my $now  = scalar localtime;

  prctl sprintf 'netdisco-daemon: worker #%s poller: wrapping up %s #%s: %s',
    $self->wid, $job->action, $job->job, $job->status;
  info sprintf "pol (%s): wrapping up %s job(%s) - status %s at %s",
    $self->wid, $job->action, $job->job, $job->status, $now;

  try {
      if ($job->status eq 'defer') {
          jq_defer($job);
      }
      else {
          $job->finished($now);
          jq_complete($job);
      }
  }
  catch { $self->sendto('stderr', "error closing job: $_\n") };
}

1;
