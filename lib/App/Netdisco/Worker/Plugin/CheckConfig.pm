package App::Netdisco::Worker::Plugin::CheckConfig;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Path::Class;
use File::ShareDir 'dist_dir';

use Alien::poetry;
use Command::Runner;

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;

  my $poetry = Alien::poetry->poetry;
  my $cipactli = Path::Class::Dir->new( dist_dir('App-Netdisco') )
    ->subdir('python')->subdir('cipactli')->stringify;
  my $config = Path::Class::Dir->new( $ENV{DANCER_ENVDIR} )
    ->file( $ENV{DANCER_ENVIRONMENT} .'.yml' );
  my $lintconf =
    q/{extends: relaxed, rules: {empty-lines: disable}}/;

  my $result = Command::Runner->new(
    command => [ $poetry, '-C', $cipactli, 'run', 'yamllint', '-d', $lintconf, $config ],
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
