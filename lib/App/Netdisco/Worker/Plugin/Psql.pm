package App::Netdisco::Worker::Plugin::Psql;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

register_worker({ stage => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $port, $extra) = map {$job->$_} qw/device port extra/;

  my $name = ($ENV{NETDISCO_DBNAME} || setting('database')->{name} || 'netdisco');
  my $host = setting('database')->{host};
  my $user = setting('database')->{user};
  my $pass = setting('database')->{pass};

  my $portnum = undef;
  if ($host and $host =~ m/([^;]+);port=(\d+)/) {
      $host = $1;
      $portnum = $2;
  }

  $ENV{PGHOST} = $host if $host;
  $ENV{PGPORT} = $portnum if defined $portnum;
  $ENV{PGDATABASE} = $name;
  $ENV{PGUSER} = $user;
  $ENV{PGPASSWORD} = $pass;
  $ENV{PGCLIENTENCODING} = 'UTF8';

  if ($extra) {
      system('psql', '-c', $extra);
  }
  else {
      system('psql');
  }

  return Status->done('psql session closed.');
});

true;
