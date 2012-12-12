package Netdisco::Daemon::Worker::Interactive;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use Netdisco::Util::DeviceProperties 'is_discoverable';
use Try::Tiny;

use Role::Tiny;
use namespace::clean;

# add dispatch methods for interactive actions
with 'Netdisco::Daemon::Worker::Interactive::DeviceActions',
     'Netdisco::Daemon::Worker::Interactive::PortActions';

sub worker_body {
  my $self = shift;

  # get all pending jobs
  my $rs = schema('netdisco')->resultset('Admin')->search({
    action => [qw/location contact portcontrol portname vlan power/],
    status => 'queued',
  });

  while (1) {
      while (my $job = $rs->next) {
          my $target = 'set_'. $job->action;
          next unless $self->can($target);

          # filter for discover_*
          next unless is_discoverable($job->device);

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
      $rs->reset;
      $self->gd_sleep( setting('daemon_sleep_time') || 5 );
  }
}

sub lock_job {
  my ($self, $job) = @_;

  # lock db table, check job state is still queued, update to running
  try {
      my $status_updated = schema('netdisco')->txn_do(sub {
          my $row = schema('netdisco')->resultset('Admin')->find(
            {job => $job->job},
            {for => 'update'}
          );

          return 0 if $row->status ne 'queued';
          $row->update({status => 'running', started => \'now()'});
          return 1;
      });

      return 0 if not $status_updated;
  }
  catch {
      warn "error locking job: $_\n";
      return 0;
  };

  return 1;
}

sub revert_job {
  my ($self, $id) = @_;

  try {
      schema('netdisco')->resultset('Admin')
        ->find($id)
        ->update({status => 'queued', started => undef});
  }
  catch {  warn "error reverting job: $_\n" };
}

sub close_job {
  my ($self, $id, $status, $log) = @_;

  try {
      schema('netdisco')->resultset('Admin')
        ->find($id)
        ->update({status => $status, log => $log, finished => \'now()'});
  }
  catch {  warn "error closing job: $_\n" };
}

1;
