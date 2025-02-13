package App::Netdisco::Worker::Plugin::Snapshot;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

register_worker({ phase => 'check' }, sub {
  return Status->error('Missing device (-d).')
    unless defined shift->device;

  return Status->defer("snapshot skipped: please run a loadmibs job first")
    unless schema('netdisco')->resultset('SNMPObject')->count();

  return Status->done('Snapshot is able to run');
});

true;
