package App::Netdisco::Backend::Worker::Poller::Expiry;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Backend::Util ':all';

use Role::Tiny;
use namespace::clean;

# expire devices and nodes according to config
sub expire {
  my ($self, $job) = @_;
  # TODO somehow run the Expire hooks?!
}

# expire nodes for a specific device
sub expirenodes {
  my ($self, $job) = @_;

  return job_error('Missing device') unless $job->device;

  schema('netdisco')->txn_do(sub {
    schema('netdisco')->resultset('Node')->search({
      switch => $job->device->ip,
      ($job->port ? (port => $job->port) : ()),
    })->delete(
      ($job->extra ? () : ({ archive_nodes => 1 }))
    );
  });

  return job_done("Expired nodes for ". $job->device->ip);
}

1;
