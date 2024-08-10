package App::Netdisco::Util::Python;

use Dancer qw/:syntax :script/;
use aliased 'App::Netdisco::Worker::Status';

use Path::Class;
use File::ShareDir 'dist_dir';

use Command::Runner;
use Alien::poetry;
use JSON::PP ();
use YAML::XS ();
use Try::Tiny;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/py_install py_cmd py_worklet/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

sub cipactli {
  my $poetry = Alien::poetry->poetry;
  my $cipactli = Path::Class::Dir->new( dist_dir('App-Netdisco') )
    ->subdir('python')->subdir('netdisco')->stringify;

  return ($poetry, '-C', $cipactli);
}

sub py_install {
  return (cipactli(), 'install', '--sync');
}

sub py_cmd {
  return (cipactli(), 'run', @_);
}

sub py_worklet {
  my ($job, $workerconf) = @_;
  my $action = $workerconf->{action};

  my $coder = JSON::PP->new->utf8(1)
                           ->allow_nonref(1)
                           ->allow_unknown(1)
                           ->allow_blessed(1)
                           ->allow_bignum(1);
  my @module = (
    $action,
    ((not $workerconf->{namespace}
      or $workerconf->{namespace} eq '_base_') ? ()
                                               : $workerconf->{namespace}),
    $workerconf->{phase},
    ($workerconf->{driver} ? $workerconf->{driver} : ()),
  );

  my $cmd = Command::Runner->new(
    env => {
      ND2_VARS          => $coder->encode( vars() ),
      ND2_JOB_METADATA  => $coder->encode( { %$job } ),
      ND2_CONFIGURATION => $coder->encode( config() ),
      # ND2_WORKER_CONFIGURATION  => $coder->encode( $workerconf ),
    },
    command => [ cipactli(), 'run', 'run_worklet', @module ],
    stderr  => sub { debug $_[0] },
    timeout => 540,
  );

  debug
    sprintf "\N{RIGHTWARDS ARROW WITH HOOK} \N{SNAKE} dispatching to \%s",
    join('.', @module);

  my $result = $cmd->run();

  debug
    sprintf "\N{LEFTWARDS ARROW WITH HOOK} \N{SNAKE} returned from \%s pid \%s exit \%s",
    join('.', @module), $result->{'pid'}, $result->{'result'};

  chomp(my $stdout = $result->{'stdout'});
  $stdout =~ s/.*\n//s;

  my $retdata = try { YAML::XS::Load($stdout) }; # might explode
  $retdata = {} if not ref $retdata or 'HASH' ne ref $retdata;

  my $status = $retdata->{status} || ($result->{'result'} ? 'error' : 'done');
  my $log = $retdata->{log}
    || ($status eq 'done' ? (sprintf '%s exit OK', $action)
                          : (sprintf '%s exit with status %s', $action, $result->{result}));

  # TODO support merging more deeply
  var($_ => $retdata->{vars}->{$_}) for keys %{ $retdata->{vars} || {} };

  return Status->$status($log);
}

true;
