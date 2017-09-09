package App::Netdisco::Worker::Plugin::ExpireNodes;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Dancer::Plugin::DBIC 'schema';

register_worker({ primary => true }, sub {
  my ($job, $workerconf) = @_;

  return Status->error('nbtstat failed: unable to interpret device param')
    if !defined $job->device;

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
