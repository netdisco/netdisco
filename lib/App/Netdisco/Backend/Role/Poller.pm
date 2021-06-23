package App::Netdisco::Backend::Role::Poller;

use Dancer qw/:moose :syntax :script/;

use Try::Tiny;
use App::Netdisco::Util::MCE;

use Time::HiRes 'sleep';
use App::Netdisco::JobQueue qw/jq_defer jq_complete/;

use Role::Tiny;
use namespace::clean;

# add dispatch methods for poller tasks
with 'App::Netdisco::Worker::Runner';

sub worker_begin { (shift)->{started} = time }

sub worker_body {
  my $self = shift;
  my $wid = $self->wid;

  while (1) {
      prctl sprintf 'nd2: #%s poll: idle', $wid;

      my $job = $self->{queue}->dequeue(1);
      next unless defined $job;

      try {
          $job->started(scalar localtime);
          prctl sprintf 'nd2: #%s poll: #%s: %s',
            $wid, $job->id, $job->display_name;
          info sprintf "pol (%s): starting %s job(%s) at %s",
            $wid, $job->action, $job->id, $job->started;
          $self->run($job);
      }
      catch {
          $job->status('error');
          $job->log("error running job: $_");
          $self->sendto('stderr', $job->log ."\n");
      };

      $self->close_job($job);
      sleep( setting('workers')->{'min_runtime'} || 0 );
      $self->exit(0); # recycle worker
  }
}

sub close_job {
  my ($self, $job) = @_;
  my $now  = scalar localtime;

  info sprintf "pol (%s): wrapping up %s job(%s) - status %s at %s",
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
