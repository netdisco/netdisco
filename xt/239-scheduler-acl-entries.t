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
# Once queued, the entry's "only" and "no" still did not hold: the device
# jobs went to every device. They were left to the skip list, which each
# backend primes from the schedule in its own configuration, and
# NETDISCO_NO_SCHEDULER (a dedicated scheduler pod) removes the schedule
# from the workers, so nothing was ever primed for the entry.
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
#     configuration overrides when they run;
#   - the scheduler job queues only the devices its entry's "only" or "no"
#     lets through, with no schedule in the worker's configuration.

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
  package FakeDevice;
  sub new { my ($c, %a) = @_; bless {%a}, $c }
  sub ip { $_[0]{ip} }
  sub name { $_[0]{name} }
}
{
  package FakeDevices;
  sub new { bless {}, shift }
  sub all { (FakeDevice->new(ip => '192.0.2.1', name => 'far-1'),
             FakeDevice->new(ip => '192.0.2.2', name => 'near-1'),
             FakeDevice->new(ip => '192.0.2.3', name => 'far-2')) }
}
{
  # the walk returns every device, as an unprimed skip list does; 192.0.2.3
  # stands for a device the walk leaves out, already queued
  package FakeRS;
  sub new { bless {}, shift }
  sub resultset { $_[1] eq 'Device' ? FakeDevices->new : $_[0] }
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

# a worker beside a dedicated scheduler, as NETDISCO_NO_SCHEDULER leaves it
delete config->{'schedule'};

$main->($job);

is_deeply [ map { $_->{device} } @queued ], ['192.0.2.1'],
  'schedulerAcl__main__only_queues_matching_devices';
is_deeply [ map { $_->{action} } @queued ], ['macsuck'],
  'schedulerAcl__main__queues_the_entry_action';

my $device_subaction = $queued[0]{subaction};

@queued = ();
my %no_entry = %$carried;
$no_entry{no} = delete $no_entry{only};
$main->(App::Netdisco::Backend::Job->new({
  job => 0, action => 'scheduler', subaction => $coder->encode(\%no_entry) }));
is_deeply [ map { $_->{device} } @queued ], ['192.0.2.2'],
  'schedulerAcl__main__no_leaves_out_matching_devices';

@queued = ();
my %device_entry = (%$carried, device => '192.0.2.2/32');
delete $device_entry{only};
$main->(App::Netdisco::Backend::Job->new({
  job => 0, action => 'scheduler', subaction => $coder->encode(\%device_entry) }));
is_deeply [ map { $_->{device} } @queued ], ['192.0.2.2'],
  'schedulerAcl__main__device_limits_the_walk';

my $device_job = App::Netdisco::Backend::Job->new({
  job => 0, action => 'macsuck', subaction => $device_subaction });
{
  local config->{'snmp_fast_connect_timeout'} = 500000;
  $device_job->apply_config_overrides;
  is setting('snmp_fast_connect_timeout'), 3000000,
    'schedulerAcl__device_job__extra_applies_as_override';
}

done_testing;
