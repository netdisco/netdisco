package App::Netdisco::Worker::Plugin::ExpireNodes;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Dancer::Plugin::DBIC 'schema';

register_worker({ stage => 'check' }, sub {
  return Status->error('Missing device (-d).')
    unless defined (shift)->device;
  return Status->done('ExpireNodes is able to run');
});

register_worker({ stage => 'main' }, sub {
  my ($job, $workerconf) = @_;

  schema('netdisco')->txn_do(sub {
    schema('netdisco')->resultset('Node')->search({
      switch => $job->device->ip,
      ($job->port ? (port => $job->port) : ()),
    })->delete(
      ($job->extra ? () : ({ archive_nodes => 1 }))
    );
  });

  return Status->done('Expired nodes for '. $job->device->ip);
});

true;
