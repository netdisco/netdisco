package App::Netdisco::Worker::Plugin::Test::Core;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

register_worker({ stage => 'main' }, sub {
  my ($job, $workerconf) = @_;
  debug 'Test (main) ran successfully.';
  return Status->done('Test (main) ran successfully (2).');
});

register_worker({ stage => 'check' }, sub {
  my ($job, $workerconf) = @_;
  debug 'Test (check) ran successfully.';
  return Status->done('Test (check) ran successfully.');
});

register_worker({ stage => 'early' }, sub {
  my ($job, $workerconf) = @_;
  debug 'Test (early) ran successfully.';
  return Status->done('Test (early) ran successfully.');
});

register_worker(sub {
  my ($job, $workerconf) = @_;
  debug 'Test (undefined) ran successfully.';
  return Status->done('Test (undefined) ran successfully.');
});

true;
