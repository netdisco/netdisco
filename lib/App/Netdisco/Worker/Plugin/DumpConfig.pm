package App::Netdisco::Worker::Plugin::DumpConfig;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Data::Printer;

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $extra = $job->extra;
  my $print_this_instead = $job->port;

  if (! $ENV{ND2_DO_QUIET}) {
      debug sprintf 'port: "%s"', ($print_this_instead || '');
      debug sprintf 'subaction: "%s"', ($extra || '');
  }

  my $key = ($print_this_instead || $extra);
  my $CONFIG = config();

  my $dump = (((defined $key) and (ref $key eq q{}))
    ? $CONFIG->{$key} : $CONFIG);
  p $dump unless $ENV{ND2_DO_QUIET};

  return Status->done($ENV{ND2_DO_QUIET}
    ? to_json($dump) : 'Dumped config');
});

true;
