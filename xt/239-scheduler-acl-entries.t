#!/usr/bin/env perl

use strict; use warnings;
no warnings 'once';

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;

use App::Netdisco;
use App::Netdisco::Backend::Job;
use App::Netdisco::Backend::Role::Scheduler ();
use App::Netdisco::Worker::Plugin::Scheduler ();

use Algorithm::Cron;
use JSON::PP ();

use Dancer qw/:moose :script !pass/;

# A schedule entry with "only" or "no" (#1106) never queued anything.
# worker_begin turns each entry's "when" into an Algorithm::Cron object, and
# the scheduler JSON-encoded the whole entry into the scheduler job, which
# JSON::PP refuses for an object: the scheduler died at the first such
# entry. Past that, the backend read the scheduler job's subaction, the
# entry, as configuration overrides and emptied it, so the job ended with
# "Missing data of Scheduler entry".
#
# Seen with walks split by hostname to give far-away devices a longer SNMP
# connect timeout through the entry's "extra".
#
# Claims, kept apart:
#   - an entry with "only" becomes one scheduler job carrying the entry, its
#     "when" left out;
#   - an entry without ACLs still becomes one job per device, as before;
#   - the scheduler job keeps its subaction, and none of the entry lands in
#     the configuration;
#   - the device jobs it queues carry the entry's "extra", which applies as
#     configuration overrides when they run.

set logger => 'null';

my $coder = JSON::PP->new->utf8(0)->allow_nonref(1);

sub entry {
  return {
    action => 'macsuck',
    only   => 'name:(?i)far.*',
    extra  => '{"snmp_fast_connect_timeout":3000000}',
    when   => Algorithm::Cron->new(base => 'local', crontab => '50 * * * *'),
    @_,
  };
}

my $carried = {
  action => 'macsuck',
  only   => 'name:(?i)far.*',
  extra  => '{"snmp_fast_connect_timeout":3000000}',
  label  => 'macwalk_far',
};

SKIP: {
  my @specs = eval { App::Netdisco::Backend::Role::Scheduler::job_specs('macwalk_far', entry()) };
  is $@, '', 'schedulerAcl__entry_with_cron_object__encodes'
    or skip 'no job specs to check', 3;
  is scalar @specs, 1, 'schedulerAcl__entry_with_only__one_scheduler_job';
  is $specs[0]{action}, 'scheduler', 'schedulerAcl__entry_with_only__action_is_scheduler';
  is_deeply $coder->decode($specs[0]{subaction}), $carried,
    'schedulerAcl__scheduler_job__carries_entry_without_when';
}

SKIP: {
  my @plain = eval { App::Netdisco::Backend::Role::Scheduler::job_specs('macwalk',
    { when => Algorithm::Cron->new(base => 'local', crontab => '50 * * * *') }) };
  is_deeply \@plain,
    [{ action => 'macwalk', device => undef, port => undef, subaction => undef }],
    'schedulerAcl__entry_without_acl__unchanged';
}

# the scheduler job as the poller runs it
my $subaction = $coder->encode($carried);
my $job = App::Netdisco::Backend::Job->new({
  job => 0, action => 'scheduler', subaction => $subaction });
$job->apply_config_overrides;
is $job->subaction, $subaction,
  'schedulerAcl__scheduler_job__subaction_kept';
ok !defined config->{'only'} && !defined config->{'extra'},
  'schedulerAcl__scheduler_job__entry_not_applied_as_configuration';

# its main worker, with the walk and the queue replaced
my @queued;
{
  package FakeRS;
  sub new { bless {}, shift }
  sub resultset { $_[0] }
  sub search { $_[0] }
  sub get_column { $_[0] }
  sub all { ('192.0.2.1', '192.0.2.2') }
}
{
  no warnings 'redefine';
  *App::Netdisco::Worker::Plugin::Scheduler::schema = sub { FakeRS->new };
  *App::Netdisco::Worker::Plugin::Scheduler::jq_insert = sub { push @queued, @{ $_[0] } };
}
my ($main) = grep { ref }
  @{ vars->{'workers'}{'scheduler'}{'main'}{'_base_'}{0} || [] };
$main->($job);

is_deeply [ map { $_->{device} } @queued ], ['192.0.2.1', '192.0.2.2'],
  'schedulerAcl__main__queues_a_job_per_device';
is_deeply [ map { $_->{action} } @queued ], ['macsuck', 'macsuck'],
  'schedulerAcl__main__queues_the_entry_action';

my $device_job = App::Netdisco::Backend::Job->new({
  job => 0, action => 'macsuck', subaction => $queued[0]{subaction} });
{
  local config->{'snmp_fast_connect_timeout'} = 500000;
  $device_job->apply_config_overrides;
  is setting('snmp_fast_connect_timeout'), 3000000,
    'schedulerAcl__device_job__extra_applies_as_override';
}

done_testing;
