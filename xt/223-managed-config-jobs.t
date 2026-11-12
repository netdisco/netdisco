#!/usr/bin/env perl

# Every backend job loads the ACL Manager roles and named groups into CONFIG
# when it starts, and the job's own config overrides are merged afterwards so
# they still win. The Poller applies overrides before Runner::run (to keep
# them out of the process title), so the load sits at the top of
# apply_config_overrides: loading later would overwrite the override.
#
# Only the two database reads are stubbed; the Runner and the loader are real.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; delete $ENV{ND2_DO_FORCE} }

use lib 'xt/lib';
use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use App::Netdisco::DB; # Device rows built in memory, never stored
use App::Netdisco::Backend::Job;
use App::Netdisco::Util::ManagedConfig qw/capture_yaml_settings/;
use Test::Netdisco::ManagedACL qw/stub_managed_config/;
use JSON::PP ();
use Dancer qw/:moose :script !pass/;

config->{logger} = 'null';
config->{extra_worker_plugins} = ['X::TestManagedConfig'];
config->{device_auth} = [];
config->{portctl_by_role} = {};
capture_yaml_settings();

{ package MyWorker;
  use Moo;
  with 'App::Netdisco::Worker::Runner';
}

my $IN  = '192.0.2.1';
my $OUT = '192.0.2.99';

sub new_job {
  my %extra = @_;
  return App::Netdisco::Backend::Job->new({
    job => 0, action => 'testmanagedconfig',
    device => App::Netdisco::DB->resultset('Device')->new_result({ ip => $IN }),
    %extra,
  });
}

# the addresses a role resolves to through its synthesized group
sub role_addresses {
  my ($report, $role) = @_;
  my $value = $report->{roles}->{$role};
  return $value if ref $value eq 'ARRAY';
  my ($group) = map { s/^group://r } keys %$value;
  return $report->{groups}->{$group};
}

sub run_job {
  my $job = shift;
  MyWorker->new->run($job);
  is($job->status, 'done', 'job is done') or diag $job->log;
  return JSON::PP->new->decode($job->log);
}

sub rows { return { netdisco => { r => { type => 'host_port', maps => [ [[ $_[0] ]] ] } } } }

subtest 'jobs__two_jobs_in_one_process__each_see_the_counter_at_their_start' => sub {
  stub_managed_config(version => 1, rows => rows($IN));
  is_deeply(role_addresses(run_job(new_job()), 'r'), [$IN], 'first job sees the first counter');

  stub_managed_config(version => 2, rows => rows($OUT), keep_cache => 1);
  is_deeply(role_addresses(run_job(new_job()), 'r'), [$OUT], 'second job sees the second counter');
};

subtest 'jobs__an_override_wins_over_the_database' => sub {
  stub_managed_config(version => 1, rows => rows($IN));
  my $report = run_job(new_job(port => '{"portctl_by_role":{"r":["198.51.100.1"]}}'));
  is_deeply($report->{roles}->{r}, ['198.51.100.1'], 'the job override beats the database role');
};

subtest 'jobs__an_override_applied_first_as_the_poller_does__still_wins' => sub {
  my $calls = stub_managed_config(version => 1, rows => rows($IN));
  my $job = new_job(port => '{"portctl_by_role":{"r":["198.51.100.1"]}}');
  $job->apply_config_overrides;
  my $report = run_job($job);
  is_deeply($report->{roles}->{r}, ['198.51.100.1'], 'the later call does not reload over the override');
  is($calls->{version_reads}, 1, 'the counter was read once for the job');
};

subtest 'jobs__the_next_job_does_not_inherit_an_override' => sub {
  stub_managed_config(version => 1, rows => rows($IN));
  run_job(new_job(port => '{"portctl_by_role":{"r":["198.51.100.1"]}}'));
  my $report = run_job(new_job());
  is_deeply(role_addresses($report, 'r'), [$IN], 'the plain job reports the database role');
};

subtest 'jobs__dumpconfig_shows_database_roles_and_named_groups' => sub {
  stub_managed_config(version => 1, rows => { netdisco => {
    r      => { type => 'host_port', maps => [ [[$IN]] ] },
    office => { type => 'host',      maps => [ [[$OUT]] ] },
  }});

  local $ENV{ND2_DO_QUIET} = 1;
  my $dump = sub {
    my $job = new_job(action => 'dumpconfig', port => shift);
    MyWorker->new->run($job);
    return JSON::PP->new->allow_nonref->decode($job->log);
  };

  my $full = JSON::PP->new->allow_nonref->decode(do {
    my $job = new_job(action => 'dumpconfig');
    MyWorker->new->run($job);
    $job->log;
  });
  ok(!exists $full->{portctl_by_role_shadow}, 'a full dump has no portctl_by_role_shadow key');

  my $roles = $dump->('portctl_by_role');
  ok(exists $roles->{r}, 'the database role is in the dump');

  my $groups = $dump->('host_groups');
  ok(exists $groups->{office}, 'the named host ACL is in the dump');
  my ($synth) = map { s/^group://r } @{ $groups->{office} };
  is_deeply($groups->{$synth}, [$OUT], 'it refers to a synthesized group holding its rules');
};

subtest 'jobs__force_still_loads' => sub {
  my $calls = stub_managed_config(version => 1, rows => rows($IN));
  local $ENV{ND2_DO_FORCE} = 1;
  run_job(new_job());
  is($calls->{version_reads}, 1, '--force does not skip the load');
};

done_testing;
