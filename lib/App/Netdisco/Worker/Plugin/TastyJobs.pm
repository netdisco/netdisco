package App::Netdisco::Worker::Plugin::TastyJobs;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Data::Printer ();
use App::Netdisco::JobQueue 'jq_getsome';

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $num_slots = ($job->extra || 20);

  my $txn_guard = schema('netdisco')->storage->txn_scope_guard;
  my @jobs = map {  { %{ $_ } } } jq_getsome($num_slots);
  undef $txn_guard;

  Data::Printer::p( @jobs );

  return Status->done("Showed the tastiest jobs");
});

true;
