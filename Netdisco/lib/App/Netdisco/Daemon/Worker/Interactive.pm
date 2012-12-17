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

  # get all pending jobs
  my $rs = schema('daemon')->resultset('Admin')->search({
    action => [qw/location contact portcontrol portname vlan power/],
    status => 'queued',
  });

  while (1) {
      while (my $job = $rs->next) {
          my $target = 'set_'. $job->action;
          next unless $self->can($target);

          # mark job as running
          next unless $self->lock_job($job);

          # do job
          my ($status, $log);
          try {
              ($status, $log) = $self->$target($job);
          }
          catch {  warn "error running job: $_\n" };

          # revert to queued status if we failed to action the job
          if (not $status) {
              $self->revert_job($job->job);
          }
          else {
              # update job state to done/error with log
              $self->close_job($job->job, $status, $log);
          }
      }

      # reset iterator so ->next() triggers another DB query
      $rs->reset;
      $self->gd_sleep( setting('daemon_sleep_time') || 5 );
  }
}

sub lock_job {
  my ($self, $job) = @_;
  my $happy = 1;

  # lock db table, check job state is still queued, update to running
  try {
      my $status_updated = schema('daemon')->txn_do(sub {
          my $row = schema('daemon')->resultset('Admin')->find(
            {job => $job->job},
            {for => 'update'}
          );

          $happy = 0 if $row->status ne 'queued';
          $row->update({status => "running-$$", started => \"datetime('now')" });
      });

      $happy = 0 if not $status_updated;
  }
  catch {
      warn "error locking job: $_\n";
      $happy = 0;
  };

  return $happy;
}

sub revert_job {
  my ($self, $id) = @_;

  try {
      schema('daemon')->resultset('Admin')
        ->find($id)
        ->update({status => 'queued', started => undef});
  }
  catch {  warn "error reverting job: $_\n" };
}

sub close_job {
  my ($self, $id, $status, $log) = @_;

  try {
      my $local =  schema('daemon')->resultset('Admin')->find($id);

      schema('netdisco')->resultset('Admin')
        ->find($id)
        ->update({
          status => $status,
          log => $log,
          started => $local->started,
          finished => \'now()',
        });

      $local->delete;
  }
  catch {  warn "error closing job: $_\n" };
}

1;
