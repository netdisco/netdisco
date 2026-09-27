#!/usr/bin/env perl

# The job action names which worker plugins to load. It is matched against
# plugin package names, so it has to be matched as text, not as a pattern.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use App::Netdisco::Backend::Job;

use Try::Tiny;
use Dancer qw/:moose :script !pass/;

config->{logger} = 'null';

{
  package MyWorker;
  use Moo;
  with 'App::Netdisco::Worker::Runner';
}

sub run_action {
  my $action = shift;
  my $job = App::Netdisco::Backend::Job->new({ job => 0, action => $action });
  my $exception = '';
  try { MyWorker->new()->run($job) } catch { $exception = $_ };
  return ($job, $exception);
}

subtest 'loadWorkers__an_action_with_a_regex_metacharacter__loads_no_plugin_it_resembles' => sub {
  delete $INC{'App/Netdisco/Worker/Plugin/Psql.pm'};
  run_action('ps.l');
  ok !exists $INC{'App/Netdisco/Worker/Plugin/Psql.pm'},
    'ps.l does not load the Psql plugin';
};

subtest 'loadWorkers__an_action_that_is_not_a_valid_pattern__fails_the_job_cleanly' => sub {
  my ($job, $exception) = run_action('(');
  is $exception, '', 'no exception escapes run()';
  is $job->status, 'error', 'the job fails as an unknown action does';
};

subtest 'loadWorkers__a_real_action_in_any_case__still_loads_its_plugin' => sub {
  delete $INC{'App/Netdisco/Worker/Plugin/Noop.pm'};
  run_action('Noop');
  ok exists $INC{'App/Netdisco/Worker/Plugin/Noop.pm'},
    'matching stays case-insensitive';
};

done_testing;
