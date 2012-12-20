package App::Netdisco::Daemon::Worker::Manager;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::DeviceProperties 'is_discoverable';
use Try::Tiny;

use Role::Tiny;
use namespace::clean;

sub worker_begin {
  my $self = shift;
  my $daemon = schema('daemon');

  # deploy local db if not already done
  try {
      $daemon->storage->dbh_do(sub {
        my ($storage, $dbh) = @_;
        $dbh->selectrow_arrayref("SELECT * FROM admin WHERE 0 = 1");
      });
  }
  catch {
      $daemon->txn_do(sub {
        $daemon->storage->disconnect;
        $daemon->deploy;
      });
  };

  $daemon->storage->disconnect;
  if ($daemon->get_db_version < $daemon->schema_version) {
      $daemon->txn_do(sub { $daemon->upgrade });
  }

  # on start, any jobs previously grabbed by a daemon on this host
  # will be reset to "queued", which is the simplest way to restart them.

  my $rs = schema('netdisco')->resultset('Admin')->search({
    status => "running-$self->{nd_host}"
  });

  if ($rs->count > 0) {
      $daemon->resultset('Admin')->delete;
      $rs->update({status => 'queued', started => undef});
  }
}

sub worker_body {
  my $self = shift;

  # get all pending jobs
  my $rs = schema('netdisco')->resultset('Admin')
    ->search({status => 'queued'});

  while (1) {
      while (my $job = $rs->next) {
          # filter for discover_*
          next unless is_discoverable($job->device);

          # mark job as running
          next unless $self->lock_job($job);

          # copy job to local queue
          $self->copy_job($job)
            or $self->revert_job($job->job);
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
      my $status_updated = schema('netdisco')->txn_do(sub {
          my $row = schema('netdisco')->resultset('Admin')->find(
            {job => $job->job},
            {for => 'update'}
          );

          $happy = 0 if $row->status ne 'queued';
          $row->update({
            status => "running-$self->{nd_host}",
            started => \'now()'
          });
      });

      $happy = 0 if not $status_updated;
  }
  catch {
      warn "error locking job: $_\n";
      $happy = 0;
  };

  return $happy;
}

sub copy_job {
  my ($self, $job) = @_;

  try {
      my %data = $job->get_columns;
      delete $data{$_} for qw/entered username userip/;

      schema('daemon')->resultset('Admin')->update_or_create({
        %data, status => 'queued', started => undef,
      });
  }
  catch {  warn "error copying job: $_\n" };
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

1;
