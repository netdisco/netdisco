package App::Netdisco::Worker::Plugin::Test;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

register_worker({ phase => 'check', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  return Status->done('Test (check) ran successfully.');
});

register_worker({ phase => 'check', priority => 100 }, sub {
  my ($job, $workerconf) = @_;
  return Status->done('Test (check 100) ran successfully.');
});

register_worker({ phase => 'check', priority => 120 }, sub {
  my ($job, $workerconf) = @_;
  return Status->done('Test (check 120) ran successfully.');
});

register_worker({ phase => 'check', driver => 'eapi' }, sub {
  my ($job, $workerconf) = @_;
  return Status->done('Test (check eapi) ran successfully.');
});

true;
