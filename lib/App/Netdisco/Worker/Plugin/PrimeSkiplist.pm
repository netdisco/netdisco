package App::Netdisco::Worker::Plugin::PrimeSkiplist;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device 'get_denied_actions';
use App::Netdisco::Util::MCE 'parse_max_workers';
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

  my $max_workers = parse_max_workers( setting('workers')->{tasks} ) || 0;

  try {
    schema(vars->{'tenant'})->txn_do(sub {
      $rs->update_or_create({
        backend => setting('workers')->{'BACKEND'},
        device  => $_,
        actionset => $actionset{$_},
      }, { key => 'primary' }) for keys %actionset;
    });

    # add one faux record to allow *walk actions to see there is a backend running
    $rs->update_or_create({
      backend => setting('workers')->{'BACKEND'},
      device  => '255.255.255.255',
      last_defer => \'LOCALTIMESTAMP',
      deferrals => $max_workers,
    }, { key => 'primary' });

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
