#!/usr/bin/env perl

# The backend reaches the main database as schema('netdisco') and as
# schema(vars->{'tenant'}), and vars->{'tenant'} is only ever set by the web.
# 'netdisco' is an alias of 'default', but DBICx::Sugar caches a schema under
# the name it was asked for, so a process that asks for 'netdisco' first
# builds a second schema, and a second connection, when it later asks for
# undef. A worker holding a lock on one connection then waits on itself on
# the other. #1782 hung this way on 2.116000, when the PostgreSQL version
# check asked for 'netdisco' in the backend's master process on DBICx::Sugar
# older than 0.0200. The runner now names the tenant 'netdisco' when nothing
# else has, so call order cannot split a worker again.
#
# Each case runs in its own process, because the schema cache is per process
# and the first name asked for is what decides the outcome. No database is
# needed: a schema does not connect until it is used.

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use App::Netdisco::DB; # fake device row
use App::Netdisco::Backend::Job;

use POSIX ();
use Scalar::Util 'refaddr';
use Try::Tiny;
use Dancer qw/:moose :script !pass/;
use Dancer::Plugin::DBIC 'schema';

config->{logger} = 'null';
config->{enable_python_worklets} = 0;
config->{device_auth} = [ { tag => 'any', driver => 'snmp' } ];

{
  package MyWorker;
  use Moo;
  with 'App::Netdisco::Worker::Runner';
}

# runs $code in a child and returns the line it printed
sub in_child {
  my $code = shift;
  pipe(my $reader, my $writer) or die "pipe: $!";
  my $pid = fork;
  die "fork: $!" unless defined $pid;
  if ($pid == 0) {
      close $reader;
      my $out = try { $code->() } catch { "died: $_" };
      print {$writer} $out;
      close $writer;
      POSIX::_exit(0);
  }
  close $writer;
  my $line = do { local $/; <$reader> };
  waitpid $pid, 0;
  return $line;
}

sub run_job {
  my $job = App::Netdisco::Backend::Job->new({
    job => 42, device => '192.0.2.1', action => 'dumpconfig', port => 'snmptimeout',
  });
  $job->device( App::Netdisco::DB->resultset('Device')->new_result({ip => '192.0.2.1'}) );
  local $ENV{ND2_DO_QUIET} = 1;
  MyWorker->new()->run($job);
  return $job;
}

sub same_schema { refaddr(schema(vars->{'tenant'})) == refaddr(schema('netdisco')) ? 'same' : 'split' }

subtest 'schemaCache__netdisco_asked_for_first__splits_without_a_tenant' => sub {
  is in_child(sub { schema('netdisco'); same_schema() }), 'split',
    'the premise: without a tenant, netdisco first gives two schemas';
};

subtest 'runner__netdisco_asked_for_first__job_uses_one_schema' => sub {
  my $out = in_child(sub {
    schema('netdisco');
    my $job = run_job();
    return join ' ', (vars->{'tenant'} // 'undef'), same_schema(), $job->status;
  });
  is $out, 'netdisco same done', 'the runner names the tenant, so both names are one schema';
};

subtest 'runner__tenant_already_set__left_alone' => sub {
  my $out = in_child(sub {
    var(tenant => 'other');
    run_job();
    return vars->{'tenant'};
  });
  is $out, 'other', 'a tenant set before the job runs is kept';
};

done_testing;
