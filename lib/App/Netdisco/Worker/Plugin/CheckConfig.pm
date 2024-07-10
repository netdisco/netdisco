package App::Netdisco::Worker::Plugin::CheckConfig;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Python qw/py_cmd/;
use Command::Runner;

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;

  my $config = Path::Class::Dir->new( $ENV{DANCER_ENVDIR} )
    ->file( $ENV{DANCER_ENVIRONMENT} .'.yml' )->stringify;
  my $lintconf =
    q/{extends: relaxed, rules: {empty-lines: disable}}/;

  my $result = Command::Runner->new(
    command => [ py_cmd('yamllint'), '-d', $lintconf, $config ],
    timeout => 60,
  )->run();

  # debug $result->{stderr};
  info $result->{stdout} if $result->{stdout};

  if (not $result->{'result'}) {
    return Status->done('Configuration OK');
  }
  else {
    return Status->error('Configuration Errors');
  }
});

true;
