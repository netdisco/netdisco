package App::Netdisco::Daemon::Worker::Interactive;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';
use Try::Tiny;

use Role::Tiny;
use namespace::clean;

# add dispatch methods for interactive actions
with 'App::Netdisco::Daemon::Worker::Interactive::DeviceActions',
     'App::Netdisco::Daemon::Worker::Interactive::PortActions';

sub worker_body {
  my $self = shift;
  my $wid = $self->wid;

  while (1) {
      debug "int ($wid): asking for a job";
      my $jobs = $self->do('take_jobs', $self->wid, 'Interactive');

      foreach my $candidate (@$jobs) {
          # create a row object so we can use column accessors
          # use the local db schema in case it is accidentally 'stored'
          # (will throw an exception)
          my $job = schema('daemon')->resultset('Admin')
                      ->new_result($candidate);
          my $jid = $job->job;

          my $target = 'set_'. $job->action;
          next unless $self->can($target);
          debug "int ($wid): can ${target}() for job $jid";

          # do job
          my ($status, $log);
          try {
              $job->started(scalar localtime);
              info sprintf "int (%s): starting job %s at %s", $wid, $jid, $job->started;
              ($status, $log) = $self->$target($job);
          }
          catch {
              $status = 'error';
              $log = "error running job: $_";
              $self->sendto('stderr', $log ."\n");
          };

          $self->close_job($job, $status, $log);
      }

      debug "int ($wid): sleeping now...";
      sleep( setting('daemon_sleep_time') || 5 );
  }
}

sub close_job {
  my ($self, $job, $status, $log) = @_;
  my $now = scalar localtime;
  info sprintf "int (%s): wrapping up job %s - status %s at %s",
    $self->wid, $job->job, $status, $now;

  try {
      schema('netdisco')->resultset('Admin')
        ->find($job->job)
        ->update({
          status => $status,
          log => $log,
          started => $job->started,
          finished => $now,
        });
  }
  catch { $self->sendto('stderr', "error closing job: $_\n") };
}

1;
