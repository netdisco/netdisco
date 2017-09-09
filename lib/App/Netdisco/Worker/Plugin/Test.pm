package App::Netdisco::Worker::Plugin::Test;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

register_worker({ primary => true }, sub {
  my ($job, $workerconf) = @_;
  debug 'Test (primary) ran successfully.';
  return Status->done('Test (primary) ran successfully.');
});

register_worker({ primary => false }, sub {
  my ($job, $workerconf) = @_;
  debug 'Test ran successfully.';
  return Status->done('Test ran successfully.');
});

true;
