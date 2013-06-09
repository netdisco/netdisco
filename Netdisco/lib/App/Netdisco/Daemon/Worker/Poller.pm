package App::Netdisco::Daemon::Worker::Poller;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use Try::Tiny;

use Role::Tiny;
use namespace::clean;

# add dispatch methods for poller tasks
with 'App::Netdisco::Daemon::Worker::Poller::Device';
with 'App::Netdisco::Daemon::Worker::Poller::Arpnip';
with 'App::Netdisco::Daemon::Worker::Poller::Macsuck';

sub worker_body {
  my $self = shift;
  my $wid = $self->wid;

  while (1) {
      debug "poll ($wid): asking for a job";
      my $jobs = $self->do('take_jobs', $self->wid, 'Poller');

      foreach my $candidate (@$jobs) {
          # create a row object so we can use column accessors
          # use the local db schema in case it is accidentally 'stored'
          # (will throw an exception)
          my $job = schema('daemon')->resultset('Admin')
                      ->new_result($candidate);
          my $jid = $job->job;
          my $target = $job->action;

          next unless $self->can($target);
          debug "poll ($wid): can ${target}() for job $jid";

          # do job
          my ($status, $log);
          try {
              $job->started(scalar localtime);
              info sprintf "poll (%s): starting %s job(%s) at %s",
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

      debug "poll ($wid): sleeping now...";
      sleep( setting('workers')->{sleep_time} || 5 );
  }
}

sub close_job {
  my ($self, $job, $status, $log) = @_;
  my $now = scalar localtime;
  info sprintf "poll (%s): wrapping up %s job(%s) - status %s at %s",
    $self->wid, $job->action, $job->job, $status, $now;

  try {
      schema('netdisco')->resultset('Admin')
        ->find($job->job, {for => 'update'})
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
