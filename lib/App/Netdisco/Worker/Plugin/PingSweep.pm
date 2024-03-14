package App::Netdisco::Worker::Plugin::PingSweep;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::JobQueue 'jq_insert';

use Time::HiRes;
use Sys::SigAction 'timeout_call';
use Net::Ping;
use Net::Ping::External;
use NetAddr::IP;

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $extra = $job->extra
    or return Status->error('missing parameter -e/extra/subaction with IP prefix');

  my $net = NetAddr::IP->new($extra);
  if (!$net or $net->num == 0 or $net->addr eq '0.0.0.0') {
      return Status->error(
        sprintf 'unable to understand as host, IP, or prefix: %s', $extra)
  }

  my @job_specs = ();
  my $ping = Net::Ping->new({proto => 'external'});

  my $pinger = sub {
    my $host = shift;
    $ping->ping($host);
    debug sprintf 'pinged %s successfully', $host;
  };

  foreach my $idx (0 .. $net->num()) {
    my $addr = $net->nth($idx) or next;
    my $host = $addr->addr;

    if (timeout_call('0.2', $pinger, $host)) {
      debug sprintf 'pinged %s and timed out', $host;
      next;
    }

    push @job_specs, {
      action => 'discover',
      device => $host,
      subaction => 'with-nodes',
      username => ($ENV{USER} || 'netdisco-do'),
    };
  }

  jq_insert( \@job_specs );
  debug sprintf 'pingsweep: queued %s jobs from %s hosts',
    (scalar @job_specs), $net->num();

  return Status->done('Finished ping sweep');
});

true;
