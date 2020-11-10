package App::Netdisco::Worker::Plugin::Hook::HTTP;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $extra = $job->extra;
  my $meta = from_json ($extra || '');

  # make http call according to config

  return Status->done('Completed http Hook');
});

true;
