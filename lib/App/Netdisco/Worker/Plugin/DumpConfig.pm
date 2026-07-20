package App::Netdisco::Worker::Plugin::DumpConfig;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Data::Printer;

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $extra = $job->extra;
  my $print_this_instead = $job->port;

  my $CONFIG = config();
  my $dump = ($extra ? $CONFIG->{$print_this_instead || $extra} : $CONFIG);
  p $dump unless $ENV{ND2_DO_QUIET};

  return Status->done($ENV{ND2_DO_QUIET}
    ? to_json($dump) : 'Dumped config');
});

true;
