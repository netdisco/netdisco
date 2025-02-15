package App::Netdisco::Worker::Plugin::Snapshot;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  return Status->error('Missing device (-d).')
    unless defined $device;

  return Status->error(sprintf 'Unknown device: %s', ($device || ''))
    unless $device and $device->in_storage;

  return Status->defer("snapshot skipped: please run a loadmibs job first")
    unless schema('netdisco')->resultset('SNMPObject')->count();

  return Status->done('Snapshot is able to run');
});

true;
