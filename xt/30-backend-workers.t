#!/usr/bin/env perl

use strict; use warnings FATAL => 'all';
use Test::More 0.88;

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::Backend::Job;

use Try::Tiny;
use Dancer qw/:moose :script !pass/;

# configure logging to force console output
my $CONFIG = config();
$CONFIG->{logger} = 'console';
$CONFIG->{log} = 'error';
Dancer::Logger->init('console', $CONFIG);

{
  package MyWorker;
  use Moo;
  with 'App::Netdisco::Worker::Runner';
}

# TESTS ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

my $j1 = do_job('TestOne');
is($j1->status, 'done', 'status is done');
is($j1->log, 'OK: SNMP driver is successful.',
  'workers are run in decreasing priority until done');

my $j2 = do_job('TestTwo');
is($j2->status, 'done', 'status is done');
is($j2->log, 'OK: CLI driver is successful.',
  'lower priority driver not run if higher is successful');

# TESTS ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

done_testing;

sub do_job {
  my $pkg = shift;

  # include local plugins
  config->{'extra_worker_plugins'} = ["X::${pkg}"];

  # clear out any previous installed hooks
  Dancer::Factory::Hook->init( Dancer::Factory::Hook->instance() );

  my $job = App::Netdisco::Backend::Job->new({
    job => 0,
    action => lc($pkg),
  });

  try {
    #info sprintf 'test: started at %s', scalar localtime;
    MyWorker->new()->run($job);
    #info sprintf 'test: %s: %s', $job->status, $job->log;
  }
  catch {
    $job->status('error');
    $job->log("error running job: $_");
  };

  return $job;
}
