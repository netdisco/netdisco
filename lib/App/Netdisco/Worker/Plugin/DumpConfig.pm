package App::Netdisco::Worker::Plugin::DumpConfig;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Data::Printer;

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $extra = $job->extra;

  my $config = config();
  my $dump = ($extra ? $config->{$extra} : $config);
  p $dump;
  return Status->done('Dumped config');
});

true;
