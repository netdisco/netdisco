package App::Netdisco::Util::Python;

use Dancer qw/:syntax :script/;
use aliased 'App::Netdisco::Worker::Status';

use Path::Class;
use File::ShareDir 'dist_dir';

use Command::Runner;
use Alien::poetry;
use JSON::PP ();

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/py_install py_cmd py_worker/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

sub cipactli {
  my $poetry = Alien::poetry->poetry;
  my $cipactli = Path::Class::Dir->new( dist_dir('App-Netdisco') )
    ->subdir('python')->subdir('cipactli')->stringify;

  return ($poetry, '-C', $cipactli);
}

sub py_install {
  return (cipactli(), 'install', '--sync');
}

sub py_cmd {
  return (cipactli(), 'run', @_);
}

sub py_worker {
  my ($action, $job, $workerconf) = @_;

  my $coder = JSON::PP->new->utf8(1)
                           ->allow_nonref(1)
                           ->allow_unknown(1)
                           ->allow_blessed(1)
                           ->allow_bignum(1);

  my $cmd = Command::Runner->new(
    env => {
      ND2_JOB_CONFIGURATION     => $coder->encode( { %$job } ),
      ND2_WORKER_CONFIGURATION  => $coder->encode( $workerconf ),
      ND2_RUNTIME_CONFIGURATION => $coder->encode( config() ),
    },
    command => [ cipactli(), 'run', 'run_worker', $action ],
    stdout  => sub { print $_[0] },
    stderr  => sub { debug $_[0] },
    timeout => 540,
  );

  debug sprintf "\N{RIGHTWARDS ARROW WITH HOOK} \N{SNAKE} dispatching to \%s", $action;
  my $result = $cmd->run();
  debug sprintf "\N{LEFTWARDS ARROW WITH HOOK} \N{SNAKE} returned from \%s", $action;

  if (not $result->{'result'}) {
    return Status->done(sprintf '%s exit OK', $action);
  }
  else {
    return Status->error(sprintf '%s exit with status %s', $action, $result->{result});
  }
}

true;
