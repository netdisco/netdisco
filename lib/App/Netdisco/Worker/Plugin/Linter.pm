package App::Netdisco::Worker::Plugin::Linter;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;

# demonstrator that we can put something in vars
# and wrap/augment a python worker with some other stuff

register_worker({ phase => 'early' }, sub {
  my ($job, $workerconf) = @_;
  my $file = $job->extra and return;

  vars->{'file_to_lint'} ||=
    Path::Class::Dir->new( $ENV{DANCER_ENVDIR} )
      ->file( $ENV{DANCER_ENVIRONMENT} .'.yml' )->stringify;
});

true;
