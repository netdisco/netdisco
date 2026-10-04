#!/usr/bin/env perl

# The poller's process title carries the job's port, so overrides are taken out
# of the port first, and applying them is once per job.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use App::Netdisco::Backend::Job;
use App::Netdisco::Backend::Role::Poller;

use MIME::Base64 'encode_base64';
use JSON::XS ();
use Try::Tiny;
use Dancer qw/:moose :script !pass/;

config->{logger} = 'null';
config->{workers}->{min_runtime} = 0;

my $sentinel = 'sentinel-community-value';
my $plain_title = 'nd2: #1 poll: #42: portcontrol 192.0.2.1 Gi1/0/1';

{
  package FakeQueue;
  sub new { my ($class, $job) = @_; return bless { job => $job }, $class }
  sub dequeue { return delete $_[0]->{job} }
}

{
  package FakePoller;
  sub new { my ($class, $job) = @_; return bless { queue => FakeQueue->new($job) }, $class }
  sub wid { 1 }
  sub run { $_[0]->{title_during_run} = $0 }
  sub close_job { }
  sub exit { die "recycled\n" }
}

sub build_job {
  my $port = shift;
  return App::Netdisco::Backend::Job->new({
    job => 42,
    device => '192.0.2.1',
    action => 'portcontrol',
    port => $port,
  });
}

# runs one pass of the poller's loop and returns the title the job ran under
sub title_while_running {
  my $job = shift;
  my $poller = FakePoller->new($job);
  my $original_title = $0;
  my $error = try { App::Netdisco::Backend::Role::Poller::worker_body($poller); q{} }
              catch { $_ };
  $0 = $original_title;
  is $error, "recycled\n", 'the poller ran the job and recycled';
  return $poller->{title_during_run};
}

sub override_with_port {
  return { value => 'Gi1/0/1', with => { device_auth => [{ community => $sentinel }] } };
}

subtest 'worker_body__plain_port__titles_with_the_port' => sub {
  is title_while_running(build_job('Gi1/0/1')), $plain_title,
    'the title carries the action, device and port';
};

subtest 'worker_body__json_override_in_port__titles_with_the_residual_port' => sub {
  my $title = title_while_running(build_job(JSON::XS->new->encode(override_with_port())));
  is $title, $plain_title, 'the title carries the residual port';
  unlike $title, qr/\Q$sentinel\E/, 'the override is not in the title';
};

subtest 'worker_body__base64_override_in_port__titles_with_the_residual_port' => sub {
  my $port = encode_base64(JSON::XS->new->encode(override_with_port()), '');
  my $title = title_while_running(build_job($port));
  is $title, $plain_title, 'the title carries the residual port';
  unlike $title, qr/\Q$sentinel\E/, 'the override is not in the title';
};

subtest 'worker_body__key_value_override_in_port__titles_without_a_port' => sub {
  my $title = title_while_running(build_job("community=$sentinel"));
  is $title, 'nd2: #1 poll: #42: portcontrol 192.0.2.1 ',
    'the title carries the action and device';
  unlike $title, qr/\Q$sentinel\E/, 'the override is not in the title';
};

subtest 'apply_config_overrides__called_twice__applies_once' => sub {
  config->{snmptimeout} = 3000000;
  my $job = build_job('{"value": "snmptimeout=7000000", "with": {"snmptimeout": 9000000}}');

  $job->apply_config_overrides;
  is setting('snmptimeout'), 9000000, 'the first call applies the override';
  is $job->port, 'snmptimeout=7000000', 'the first call leaves the residual port';

  $job->apply_config_overrides;
  is setting('snmptimeout'), 9000000, 'the second call applies nothing';
  is $job->port, 'snmptimeout=7000000', 'the second call leaves the port alone';
};

subtest 'apply_config_overrides__on_a_job__adds_no_key_to_the_job' => sub {
  my $job = build_job('Gi1/0/1');
  my @keys_before = sort keys %$job;
  $job->apply_config_overrides;
  is_deeply [sort keys %$job], \@keys_before, 'the job carries the same keys';
};

subtest 'apply_config_overrides__two_jobs__each_applies' => sub {
  config->{snmptimeout} = 3000000;
  my $first  = build_job('{"value": "Gi1/0/1", "with": {"snmptimeout": 4000000}}');
  my $second = build_job('{"value": "Gi1/0/2", "with": {"snmptimeout": 5000000}}');

  $first->apply_config_overrides;
  is setting('snmptimeout'), 4000000, 'the first job applies its override';
  $second->apply_config_overrides;
  is setting('snmptimeout'), 5000000, 'the second job applies its own';
};

done_testing;
