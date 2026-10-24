#!/usr/bin/env perl

use strict; use warnings;

# A worker can die with an exception object, as DBIx::Class does. The job's
# log must be the error's text, because jq_complete stores the log only when
# it is a plain string, and an object would leave admin.log empty.

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::Backend::Job;

use Dancer qw/:moose :script !pass/;

set logger => 'null';

{
  package MyWorker;
  use Moo;
  with 'App::Netdisco::Worker::Runner';
}

config->{'device_auth'} = [{driver => 'snmp'}];
config->{'extra_worker_plugins'} = ['X::TestEight'];

subtest 'run_workers__worker_dies_with_an_object__log_is_its_text' => sub {
  my $job = App::Netdisco::Backend::Job->new({
    job => 0,
    device => App::Netdisco::DB->resultset('Device')->new_result({ip => '192.0.2.1'}),
    action => 'testeight',
  });
  MyWorker->new()->run($job);
  is($job->status, 'error');
  is(ref $job->log, '', 'a plain string, which jq_complete stores');
  like($job->log, qr/duplicate key value violates unique constraint "subnets_pkey"/);
};

done_testing;
