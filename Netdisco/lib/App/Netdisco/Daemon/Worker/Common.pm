package App::Netdisco::Daemon::Worker::Common;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';
use Try::Tiny;

use Role::Tiny;
use namespace::clean;

requires qw/worker_type worker_name munge_action/;

sub worker_body {
  my $self = shift;
  my $wid = $self->wid;

  my $type = $self->worker_type;
  my $name = $self->worker_name;

  while (1) {
      debug "$type ($wid): asking for a job";
      my $jobs = $self->do('take_jobs', $self->wid, $name);

      foreach my $candidate (@$jobs) {
          # create a row object so we can use column accessors
          # use the local db schema in case it is accidentally 'stored'
          # (will throw an exception)
          my $job = schema('daemon')->resultset('Admin')
                      ->new_result($candidate);
          my $jid = $job->job;

          my $target = $self->munge_action($job->action);
          next unless $self->can($target);
          debug "$type ($wid): can ${target}() for job $jid";

          # do job
          my ($status, $log);
          try {
              $job->started(scalar localtime);
              info sprintf "$type (%s): starting %s job(%s) at %s",
                $wid, $target, $jid, $job->started;
              ($status, $log) = $self->$target($job);
          }
          catch {
              $status = 'error';
              $log = "error running job: $_";
              $self->sendto('stderr', $log ."\n");
          };

          $self->close_job($job, $status, $log);
      }

      debug "$type ($wid): sleeping now...";
      sleep(1);
  }
}

sub close_job {
  my ($self, $job, $status, $log) = @_;
  my $type = $self->worker_type;
  my $now = scalar localtime;

  info sprintf "$type (%s): wrapping up %s job(%s) - status %s at %s",
    $self->wid, $job->action, $job->job, $status, $now;

  # lock db row and either defer or complete the job
  try {
      if ($status eq 'defer') {
          schema('netdisco')->resultset('Admin')
            ->find($job->job, {for => 'update'})
            ->update({ status => 'queued' });
      }
      else {
          schema('netdisco')->resultset('Admin')
            ->find($job->job, {for => 'update'})
            ->update({
              status => $status,
              log => $log,
              started => $job->started,
              finished => $now,
            });
      }
  }
  catch { $self->sendto('stderr', "error closing job: $_\n") };
}

1;
