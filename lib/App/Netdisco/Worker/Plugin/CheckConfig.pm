package App::Netdisco::Worker::Plugin::CheckConfig;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;

use App::Netdisco::Util::Python qw/py_worker/;

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $config = Path::Class::Dir->new( $ENV{DANCER_ENVDIR} )
    ->file( $ENV{DANCER_ENVIRONMENT} .'.yml' )->stringify;
  $job->subaction($config);
  return py_worker('linter', $job, $workerconf);
});

true;
