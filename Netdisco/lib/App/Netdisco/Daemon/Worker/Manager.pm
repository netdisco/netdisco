package App::Netdisco::Daemon::Worker::Manager;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::Device 'is_discoverable';
use Net::Domain 'hostfqdn';
use Try::Tiny;

use Role::Tiny;
use namespace::clean;

my $fqdn = hostfqdn || 'localhost';

my $role_map = {
  (map {$_ => 'Poller'}
      qw/discoverall discover arpwalk arpnip macwalk macsuck/),
  (map {$_ => 'Interactive'}
      qw/location contact portcontrol portname vlan power/)
};

sub worker_begin {
  my $self = shift;
  my $wid = $self->wid;
  debug "entering Manager ($wid) worker_begin()";

  # requeue jobs locally
  debug "mgr ($wid): searching for jobs booked to this processing node";
  my $rs = schema('netdisco')->resultset('Admin')
    ->search({status => "queued-$fqdn"});

  my @jobs = map {{$_->get_columns}} $rs->all;

  if (scalar @jobs) {
      info sprintf "mgr (%s): found %s jobs booked to this processing node", $wid, scalar @jobs;
      map { $_->{role} = $role_map->{$_->{action}} } @jobs;

      $self->do('add_jobs', \@jobs);
  }
}

sub worker_body {
  my $self = shift;
  my $wid = $self->wid;
  my $num_slots = $self->do('num_workers')
    or return debug "mgr ($wid): this node has no workers... quitting manager";

  # get some pending jobs
  my $rs = schema('netdisco')->resultset('Admin')
    ->search(
      {status => 'queued'},
      {order_by => 'random()', rows => $num_slots},
    );

  while (1) {
      debug "mgr ($wid): getting potential jobs for $num_slots workers";
      while (my $job = $rs->next) {
          my $jid = $job->job;

          # filter for discover_*
          next unless is_discoverable($job->device);
          debug sprintf "mgr (%s): job %s is discoverable", $wid, $jid;

          # check for available local capacity
          next unless $self->do('capacity_for', $job->action);
          debug sprintf "mgr (%s): processing node has capacity for job %s (%s)",
            $wid, $jid, $job->action;

          # mark job as running
          next unless $self->lock_job($job);
          info sprintf "mgr (%s): job %s booked out for this processing node",
            $wid, $jid;

          my $local_job = { $job->get_columns };
          $local_job->{role} = $role_map->{$job->action};

          # copy job to local queue
          $self->do('add_jobs', [$local_job]);
      }

      # reset iterator so ->next() triggers another DB query
      $rs->reset;

      # TODO also check for stale jobs in Netdisco DB

      debug "mgr ($wid): sleeping now...";
      sleep( setting('daemon_sleep_time') || 5 );
  }
}

sub lock_job {
  my ($self, $job) = @_;
  my $happy = 0;

  # lock db row and update to show job has been picked
  try {
      schema('netdisco')->txn_do(sub {
          my $row = schema('netdisco')->resultset('Admin')->find(
            {job => $job->job, status => 'queued'}, {for => 'update'}
          );

          $row->update({status => "queued-$fqdn"});
      });
      $happy = 1;
  };

  return $happy;
}

1;
