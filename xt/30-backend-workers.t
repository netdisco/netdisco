#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::DB; # fake device row
use App::Netdisco::Backend::Job;

use Try::Tiny;
use Dancer qw/:moose :script !pass/;

# configure logging to force console output
my $CONFIG = config();
$CONFIG->{logger} = 'console';
$CONFIG->{log} = ($ENV{'DANCER_DEBUG'} ? 'debug' : 'error');
Dancer::Logger->init('console', $CONFIG);

{
  package MyWorker;
  use Moo;
  with 'App::Netdisco::Worker::Runner';
}

# clear user device_auth and set our own
config->{'device_auth'} = [{driver => 'snmp'}, {driver => 'cli'}];

# TESTS ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

my $j1 = do_job('TestOne');
is($j1->status, 'done', 'status is done');
is($j1->log, 'OK: SNMP driver is successful.',
  'workers are run in decreasing priority until done');

my $j2 = do_job('TestTwo');
is($j2->status, 'done', 'status is done');
is($j2->log, 'OK: CLI driver is successful.',
  'lower priority driver not run if higher is successful');

config->{'device_auth'} = [];

my $j3 = do_job('TestOne');
is($j3->status, 'defer', 'status is defer');
is($j3->log, 'deferred job with no device creds',
  'no matching config for workers');

config->{'device_auth'} = [{driver => 'snmp'}];

my $j4 = do_job('TestThree');
is($j4->status, 'done', 'status is done');
is($j4->log, 'OK: SNMP driver is successful.',
  'respect user config filtering the driver');

config->{'device_auth'} = [
  {driver => 'snmp', action => 'testthree'},
  {driver => 'cli',  action => 'foo'},
];

my $j5 = do_job('TestThree');
is($j5->status, 'done', 'status is done');
is($j5->log, 'OK: SNMP driver is successful.',
  'respect user config filtering the action');

config->{'device_auth'} = [
  {driver => 'snmp', action => 'testthree::_base_'},
  {driver => 'cli',  action => 'testthree::foo'},
];

my $j6 = do_job('TestThree');
is($j6->status, 'done', 'status is done');
is($j6->log, 'OK: SNMP driver is successful.',
  'respect user config filtering the namespace');

config->{'device_auth'} = [{driver => 'snmp'}];

my $j7 = do_job('TestFour');
is($j7->status, 'done', 'status is done');
is($j7->log, 'OK: custom driver is successful.',
  'override an action');

config->{'device_auth'} = [{driver => 'snmp'}];

my $j8 = do_job('TestFive');
is($j8->status, 'done', 'status is done');
is((scalar @{$j8->_statuslist}), 2, 'two workers ran');
is($j8->log, 'OK: SNMP driver is successful.',
  'add to an action');

config->{'device_auth'} = [];

my $j9 = do_job('TestSix');
is($j9->status, 'done', 'status is done');
is((scalar @{$j9->_statuslist}), 3, 'three workers ran');
is($j9->log, 'OK: second driverless action is successful.',
  'driverless actions always run');

my $j10 = do_job('TestSeven');
is($j10->best_status, 'error', 'status is error');
is((scalar @{$j10->_statuslist}), 2, 'two workers ran');

done_testing;

# TESTS ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub do_job {
  my $pkg = shift;

  # include local plugins
  config->{'extra_worker_plugins'} = ["X::${pkg}"];

  my $job = App::Netdisco::Backend::Job->new({
    job => 0,
    device => App::Netdisco::DB->resultset('Device')->new_result({ip => '192.0.2.1'}),
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
