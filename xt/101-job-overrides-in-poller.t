#!/usr/bin/env perl

# A job's extra can carry configuration overrides, such as
# {"device_auth_tag_hint": "...", "snmptimeout": ...}. A queued job is built
# in the backend manager (jq_getsome) and handed to a poller, a separate
# process, through MCE::Queue. The overrides used to be applied while the job
# was built, so they changed only the manager's configuration, for good, and
# the poller received a job with nothing left to apply. netdisco-do builds and
# runs a job in one process, which is why it still worked there.
#
# These build the job in another process, pass it through Sereal as
# MCE::Queue does, and run it here, checking what the job saw.

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::DB; # fake device row
use App::Netdisco::Backend::Job;

use POSIX ();
use Sereal::Encoder ();
use Sereal::Decoder ();
use JSON::XS ();
use Try::Tiny;
use Dancer qw/:moose :script !pass/;

config->{logger} = 'null';
config->{enable_python_worklets} = 0; # dumpconfig is Perl, and CI has no python venv to start

{
  package MyWorker;
  use Moo;
  with 'App::Netdisco::Worker::Runner';
}

# the manager's side: build the job from its stored columns
sub build_job {
  my ($extra, $dump) = @_;
  return App::Netdisco::Backend::Job->new({
    job => 42,
    device => '192.0.2.1',
    action => 'dumpconfig',
    subaction => $extra,
    port => $dump,
  });
}

# the manager and the queue: the job is built in another process, as it is
# in the backend, and comes over as Sereal, which is what netdisco-backend-fg
# loads MCE::Flow with. Building it in this process instead would let the old
# behaviour pass, since the overrides would then land where the job runs.
sub queued_job {
  my @args = @_;
  pipe(my $reader, my $writer) or die "pipe: $!";
  my $pid = fork;
  die "fork: $!" unless defined $pid;
  if ($pid == 0) {
      close $reader;
      binmode $writer;
      print {$writer} Sereal::Encoder->new->encode(build_job(@args));
      close $writer;
      POSIX::_exit(0);
  }
  close $writer;
  binmode $reader;
  my $frozen = do { local $/; <$reader> };
  waitpid $pid, 0;
  return Sereal::Decoder->new->decode($frozen);
}

# the poller's side: run it, and read back what dumpconfig saw
sub run_job {
  my $job = shift;
  $job->device( App::Netdisco::DB->resultset('Device')->new_result({ip => $job->device}) );
  local $ENV{ND2_DO_QUIET} = 1; # dumpconfig logs its result as JSON
  try { MyWorker->new()->run($job) }
  catch { $job->status('error'); $job->log("error running job: $_") };
  is $job->status, 'done', 'the job completes' or diag $job->log;
  return try { JSON::XS->new->allow_nonref->decode($job->log) };
}

# a poller starts from the configuration it was forked with
sub fresh_config {
  config->{snmptimeout} = 3000000;
  config->{device_auth_tag_hint} = undef;
  config->{device_auth} = [
    { tag => 'first',  driver => 'snmp' },
    { tag => 'hinted', driver => 'snmp' },
  ];
}

subtest 'jobOverrides__building_a_queued_job__leaves_the_builders_config_alone' => sub {
  fresh_config();
  build_job('{"snmptimeout": 9000000, "device_auth_tag_hint": "hinted"}');
  is setting('snmptimeout'), 3000000, 'snmptimeout is unchanged where the job was built';
  is setting('device_auth_tag_hint'), undef, 'the tag hint is unchanged where the job was built';
};

subtest 'jobOverrides__a_queued_job__applies_its_override_in_the_poller' => sub {
  fresh_config();
  my $job = queued_job('{"snmptimeout": 9000000}', 'snmptimeout');
  is run_job($job), 9000000, 'the job ran with its snmptimeout';
  is $job->subaction, q{}, 'the override is consumed from subaction as before';
};

subtest 'jobOverrides__a_queued_job_with_a_tag_hint__tries_the_hinted_entry_first' => sub {
  fresh_config();
  my $job = queued_job('{"device_auth_tag_hint": "hinted"}', 'device_auth');
  is_deeply [map { $_->{tag} } @{ run_job($job) || [] }], [qw/hinted first/],
    'the hinted device_auth entry was promoted for the job';
};

done_testing;
