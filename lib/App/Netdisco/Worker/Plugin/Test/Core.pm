package App::Netdisco::Worker::Plugin::Test::Core;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

register_worker({ stage => 'second' }, sub {
  my ($job, $workerconf) = @_;
  debug 'Test (second) ran successfully.';
  return Status->done('Test (second) ran successfully.');
});

register_worker({ stage => 'check' }, sub {
  my ($job, $workerconf) = @_;
  debug 'Test (check) ran successfully.';
  return Status->done('Test (check) ran successfully.');
});

register_worker({ stage => 'first' }, sub {
  my ($job, $workerconf) = @_;
  debug 'Test (first) ran successfully.';
  return Status->done('Test (first) ran successfully.');
});

register_worker(sub {
  my ($job, $workerconf) = @_;
  debug 'Test (undefined) ran successfully.';
  return Status->done('Test (undefined) ran successfully.');
});

true;
