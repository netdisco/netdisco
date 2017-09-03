package App::Netdisco::Backend::Worker::Poller;

use Dancer qw/:moose :syntax :script/;

use Try::Tiny;
use App::Netdisco::Util::MCE;

use Role::Tiny;
use namespace::clean;

use Time::HiRes 'sleep';
use App::Netdisco::JobQueue qw/jq_defer jq_complete/;

# add dispatch methods for poller tasks
with 'App::Netdisco::Backend::Worker::Poller::Device',
     'App::Netdisco::Backend::Worker::Poller::Arpnip',
     'App::Netdisco::Backend::Worker::Poller::Macsuck',
     'App::Netdisco::Backend::Worker::Poller::Nbtstat',
     'App::Netdisco::Backend::Worker::Poller::Expiry',
     'App::Netdisco::Backend::Worker::Interactive::DeviceActions',
     'App::Netdisco::Backend::Worker::Interactive::PortActions';

sub worker_begin { (shift)->{started} = time }

sub worker_body {
  my $self = shift;
  my $wid = $self->wid;

  while (1) {
      prctl sprintf 'nd2: #%s poll: idle', $wid;

      my $job = $self->{queue}->dequeue(1);
      next unless defined $job;
      my $action = $job->action;

      try {
          $job->started(scalar localtime);
          prctl sprintf 'nd2: #%s poll: #%s: %s',
            $wid, $job->job, $job->summary;
          info sprintf "pol (%s): starting %s job(%s) at %s",
            $wid, $action, $job->job, $job->started;
          my $status = $self->$action($job); # TODO
          $status->update_job($job);
      }
      catch {
          $job->status('error');
          $job->log("error running job: $_");
          $self->sendto('stderr', $job->log ."\n");
      };

      $self->close_job($job);
      sleep( setting('workers')->{'min_runtime'} || 0 );
      $self->exit(0); # recycle worker
  }
}

sub close_job {
  my ($self, $job) = @_;
  my $now  = scalar localtime;

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
