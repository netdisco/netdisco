package App::Netdisco::Worker::Plugin::Psql;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $port, $extra) = map {$job->$_} qw/device port extra/;

  my $name = setting('database')->{name};
  my $host = setting('database')->{host};
  my $user = setting('database')->{user};
  my $pass = setting('database')->{pass};

  my $portnum = undef;
  if ($host and $host =~ m/([^;]+);(.+)/) {
      $host = $1;
      my $extra = $2;
      my @opts = split(/;/, $extra);
      debug sprintf("Host: %s, extra: %s\n", $host, $extra);
      foreach my $opt (@opts) {
        if ($opt =~ m/port=(\d+)/) {
            $portnum = $1;
        } else {
            # Unhandled connection option, ignore for now
        }
      }
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
