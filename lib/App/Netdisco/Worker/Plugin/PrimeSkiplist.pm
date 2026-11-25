package App::Netdisco::Worker::Plugin::PrimeSkiplist;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device 'get_denied_actions';
use App::Netdisco::Backend::Queues 'total_workers';
use App::Netdisco::Backend::Job;

use Try::Tiny;

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $happy = false;

  my $devices = schema(vars->{'tenant'})->resultset('Device');
  my $rs = schema(vars->{'tenant'})->resultset('DeviceSkip');
  my %actionset = ();

  while (my $d = $devices->next) {
    my @badactions = get_denied_actions($d);
    $actionset{$d->ip} = \@badactions if scalar @badactions;
  }

  debug sprintf 'priming device action skip list for %d devices',
    scalar keys %actionset;

  my $max_workers = total_workers();

  my $backend = setting('workers')->{'BACKEND'};

  # one upsert in key order rather than a select-then-write per device:
  # backends that share a BACKEND name, such as the replicas of one
  # deployment, prime at the same time on start, and their writes raced
  # into duplicate keys and deadlocks
  try {
    schema(vars->{'tenant'})->txn_do(sub {
      $rs->upsert([ map {{
        backend => $backend,
        device  => $_,
        actionset => $actionset{$_},
      }} keys %actionset ]);
    });

    # add one faux record to allow *walk actions to see there is a backend running
    $rs->upsert([{
      backend => $backend,
      device  => '255.255.255.255',
      last_defer => \'LOCALTIMESTAMP',
      deferrals => $max_workers,
    }]);

    $happy = true;
  }
  catch {
    error $_;
  };

  if ($happy) {
    return Status->done("Primed device action skip list");
  }
  else {
    return Status->error("Failed to prime device action skip list");
  }
});

true;
