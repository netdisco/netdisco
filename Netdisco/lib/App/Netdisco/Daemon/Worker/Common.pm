package App::Netdisco::Daemon::Worker::Common;

use Dancer qw/:moose :syntax :script/;

use Try::Tiny;
use App::Netdisco::Util::Daemon;

use Role::Tiny;
use namespace::clean;

use App::Netdisco::JobQueue qw/jq_take jq_defer jq_complete/;

sub worker_body {
  my $self = shift;
  my $wid = $self->wid;

  my $tag  = $self->worker_tag;
  my $type = $self->worker_type;

  while (1) {
      prctl sprintf 'netdisco-daemon: worker #%s %s: idle', $wid, lc($type);
      my $jobs = jq_take($self->wid, $type);

      foreach my $job (@$jobs) {
          my $target = $self->munge_action($job->action);

          try {
              $job->started(scalar localtime);
              prctl sprintf 'netdisco-daemon: worker #%s %s: working on #%s: %s',
                $wid, lc($type), $job->id, $job->summary;
              info sprintf "$tag (%s): starting %s job(%s) at %s",
                $wid, $target, $job->id, $job->started;
              my ($status, $log) = $self->$target($job);
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
}

sub close_job {
  my ($self, $job) = @_;
  my $tag  = $self->worker_tag;
  my $type = $self->worker_type;
  my $now  = scalar localtime;

  prctl sprintf 'netdisco-daemon: worker #%s %s: wrapping up %s #%s: %s',
    $self->wid, lc($type), $job->action, $job->id, $job->status;
  info sprintf "$tag (%s): wrapping up %s job(%s) - status %s at %s",
    $self->wid, $job->action, $job->id, $job->status, $now;

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
